param(
    [ValidateSet("install", "update", "upgrade", "help")]
    [string]$Command = "install",
    [string]$PackageId = ""
)

$ErrorActionPreference = "Stop"
$PowerShellStableBuildInfoUrl = "https://aka.ms/pwsh-buildinfo-stable"

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Show-Usage {
    @"
Usage: windows.ps1 [install|update|upgrade|help]
       windows.ps1 install|upgrade <package-id>

Commands:
  install  Install baseline packages
  update   Update winget sources
  upgrade  Upgrade managed baseline packages only
"@
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-LocalAppData {
    if ($env:LOCALAPPDATA) {
        return $env:LOCALAPPDATA
    }

    return Join-Path $HOME "AppData\Local"
}

function Update-ProcessPath {
    $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $KnownUserPaths = @(
        (Join-Path (Get-LocalAppData) "Microsoft\WindowsApps"),
        (Join-Path (Get-LocalAppData) "Microsoft\WinGet\Links")
    )
    $Seen = @{}
    $PathParts = @()

    foreach ($PathEntry in (@($MachinePath, $UserPath, $env:Path) + $KnownUserPaths)) {
        foreach ($Part in ([string]$PathEntry -split ";")) {
            if ([string]::IsNullOrWhiteSpace($Part)) {
                continue
            }

            $Key = $Part.Trim().ToLowerInvariant()
            if (-not $Seen.ContainsKey($Key)) {
                $Seen[$Key] = $true
                $PathParts += $Part.Trim()
            }
        }
    }

    $env:Path = $PathParts -join ";"
}

function Assert-Winget {
    if (-not (Test-Command "winget")) {
        Write-DotfilesLog "winget is required for this script"
        exit 1
    }
}

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Name,
        [string[]]$Commands = @(),
        [string[]]$Paths = @()
    )

    $CommandList = @($Commands | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $PathList = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($CommandList.Count -gt 0 -or $PathList.Count -gt 0) {
        $MissingCommands = @($CommandList | Where-Object { -not (Test-Command $_) })
        $MissingPaths = @($PathList | Where-Object { -not (Test-Path -Path $_ -PathType Leaf) })
        if ($MissingCommands.Count -eq 0 -and $MissingPaths.Count -eq 0) {
            Write-DotfilesLog "already installed: $Name"
            return
        }
    }

    Assert-Winget
    Write-DotfilesLog "installing $Name"
    winget install --id $Id --exact --accept-package-agreements --accept-source-agreements
    Update-ProcessPath
}

function Upgrade-WingetPackage {
    param(
        [string]$Id,
        [string]$Name
    )

    Assert-Winget
    Write-DotfilesLog "upgrading $Name"
    winget upgrade --id $Id --exact --accept-package-agreements --accept-source-agreements
}

function ConvertTo-VersionOrNull {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $VersionText = ($Value -replace "^[^0-9]*", "" -replace "[^0-9.].*$", "")
    try {
        return [Version]$VersionText
    }
    catch {
        return $null
    }
}

function Get-PowerShellVersion {
    if (-not (Test-Command "pwsh")) {
        return ""
    }

    try {
        $Output = & pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
        if ($LASTEXITCODE -eq 0 -and $Output) {
            return ($Output | Select-Object -First 1).Trim()
        }
    }
    catch {
    }

    return ""
}

function Get-PowerShellStableReleaseInfo {
    try {
        $Release = Invoke-RestMethod -Uri $PowerShellStableBuildInfoUrl -Headers @{ "User-Agent" = "dotfiles" } -ErrorAction Stop
        $Tag = [string]$Release.ReleaseTag
        if ([string]::IsNullOrWhiteSpace($Tag)) {
            Write-DotfilesLog "PowerShell stable release metadata is missing ReleaseTag"
            exit 1
        }

        $VersionText = $Tag -replace "^v", ""
        $Version = ConvertTo-VersionOrNull $VersionText
        if ($null -eq $Version) {
            Write-DotfilesLog "PowerShell stable release metadata has invalid ReleaseTag: $Tag"
            exit 1
        }

        return [PSCustomObject]@{
            Tag = $Tag
            VersionText = $VersionText
            Version = $Version
            ReleaseDate = [string]$Release.ReleaseDate
        }
    }
    catch {
        Write-DotfilesLog "failed to query PowerShell stable release metadata"
        exit 1
    }
}

function Test-PowerShellReleaseCurrent {
    param([Version]$ReleaseVersion)

    $Current = ConvertTo-VersionOrNull (Get-PowerShellVersion)
    return $null -ne $Current -and $Current -ge $ReleaseVersion
}

function Get-PowerShellInstallerArchitecture {
    $Architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()

    switch ($Architecture) {
        "x64" { return "x64" }
        "arm64" { return "arm64" }
        "x86" { return "x86" }
        default {
            Write-DotfilesLog "unsupported PowerShell installer architecture: $Architecture"
            exit 1
        }
    }
}

function Install-PowerShellRelease {
    param([string]$VersionText)

    $Architecture = Get-PowerShellInstallerArchitecture
    $AssetName = "PowerShell-$VersionText-win-$Architecture.msi"
    $Url = "https://github.com/PowerShell/PowerShell/releases/download/v$VersionText/$AssetName"
    $InstallerPath = Join-Path ([System.IO.Path]::GetTempPath()) $AssetName

    if (-not (Test-Path -Path $InstallerPath -PathType Leaf)) {
        Write-DotfilesLog "downloading PowerShell $VersionText from GitHub release"
        Invoke-WebRequest -Uri $Url -OutFile $InstallerPath
    }
    else {
        Write-DotfilesLog "using cached PowerShell installer: $InstallerPath"
    }

    try {
        Write-DotfilesLog "installing PowerShell $VersionText from GitHub release"
        $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", $InstallerPath, "/quiet", "/norestart") -Wait -PassThru
        if ($Process.ExitCode -ne 0 -and $Process.ExitCode -ne 3010) {
            Write-DotfilesLog "PowerShell MSI install failed with exit code $($Process.ExitCode)"
            exit $Process.ExitCode
        }

        if ($Process.ExitCode -eq 3010) {
            Write-DotfilesLog "PowerShell MSI install completed; restart may be required"
        }
    }
    finally {
        Remove-Item -LiteralPath $InstallerPath -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-PowerShellReleaseCurrent (ConvertTo-VersionOrNull $VersionText))) {
        Write-DotfilesLog "PowerShell $VersionText may require a shell restart before it is active"
    }
}

function Invoke-PackageInstall {
    param([hashtable]$Package)

    if ($Package.ComponentId -eq "package-pwsh") {
        $Release = Get-PowerShellStableReleaseInfo
        if (Test-PowerShellReleaseCurrent $Release.Version) {
            Write-DotfilesLog "PowerShell already meets GitHub stable release $($Release.Tag)"
            return
        }

        Install-PowerShellRelease -VersionText $Release.VersionText
        return
    }

    Install-WingetPackage -Id $Package.Id -Name $Package.Name -Commands $Package.Commands -Paths $Package.Paths
}

function Invoke-PackageUpgrade {
    param([hashtable]$Package)

    if ($Package.ComponentId -eq "package-pwsh") {
        $Release = Get-PowerShellStableReleaseInfo
        if (Test-PowerShellReleaseCurrent $Release.Version) {
            Write-DotfilesLog "PowerShell already meets GitHub stable release $($Release.Tag)"
            return
        }

        Install-PowerShellRelease -VersionText $Release.VersionText
        return
    }

    Upgrade-WingetPackage -Id $Package.Id -Name $Package.Name
}

function Update-WingetSources {
    Assert-Winget
    Write-DotfilesLog "updating winget sources"
    winget source update
}

function Select-Packages {
    param([string]$Id)

    if ([string]::IsNullOrWhiteSpace($Id)) {
        return $Packages
    }

    $Selected = @($Packages | Where-Object { $_.ComponentId -eq $Id -or $_.Id -eq $Id })
    if ($Selected.Count -eq 0) {
        Write-DotfilesLog "unknown Windows package id: $Id"
        exit 1
    }

    return $Selected
}

$Packages = @(
    @{ ComponentId = "package-git"; Id = "Git.Git"; Name = "Git"; Commands = @("git") },
    @{ ComponentId = "package-msys2"; Id = "MSYS2.MSYS2"; Name = "MSYS2"; Paths = @("C:\msys64\usr\bin\pacman.exe") },
    @{ ComponentId = "package-chezmoi"; Id = "twpayne.chezmoi"; Name = "chezmoi"; Commands = @("chezmoi") },
    @{ ComponentId = "package-nvim"; Id = "Neovim.Neovim"; Name = "Neovim"; Commands = @("nvim") },
    @{ ComponentId = "package-wezterm"; Id = "wez.wezterm"; Name = "WezTerm"; Commands = @("wezterm") },
    @{ ComponentId = "package-ripgrep"; Id = "BurntSushi.ripgrep.MSVC"; Name = "ripgrep"; Commands = @("rg") },
    @{ ComponentId = "package-fd"; Id = "sharkdp.fd"; Name = "fd"; Commands = @("fd") },
    @{ ComponentId = "package-fzf"; Id = "junegunn.fzf"; Name = "fzf"; Commands = @("fzf") },
    @{ ComponentId = "package-eza"; Id = "eza-community.eza"; Name = "eza"; Commands = @("eza") },
    @{ ComponentId = "dependency-rust"; Id = "Rustlang.Rustup"; Name = "Rustup"; Commands = @("rustc", "cargo") },
    @{ ComponentId = "package-pwsh"; Id = "Microsoft.PowerShell"; Name = "PowerShell"; Commands = @("pwsh") }
)

if ($Command -eq "help") {
    Show-Usage
    exit 0
}

Update-ProcessPath

switch ($Command) {
    "install" {
        foreach ($Package in (Select-Packages $PackageId)) {
            Invoke-PackageInstall -Package $Package
        }
        Write-DotfilesLog "Windows package setup complete"
    }
    "update" {
        Update-WingetSources
    }
    "upgrade" {
        $SelectedPackages = @(Select-Packages $PackageId)
        if (@($SelectedPackages | Where-Object { $_.ComponentId -ne "package-pwsh" }).Count -gt 0) {
            Update-WingetSources
        }

        foreach ($Package in $SelectedPackages) {
            Invoke-PackageUpgrade -Package $Package
        }
        Write-DotfilesLog "Windows managed package upgrade complete"
    }
}
