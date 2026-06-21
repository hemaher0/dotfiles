param(
    [ValidateSet("install", "update", "upgrade", "help")]
    [string]$Command = "install",
    [string]$PackageId = ""
)

$ErrorActionPreference = "Stop"

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Show-Usage {
    @"
Usage: windows.ps1 [install|update|upgrade|help]
       windows.ps1 install|upgrade <package-id>

Commands:
  install  Install baseline packages with winget
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

    Write-DotfilesLog "installing $Name"
    winget install --id $Id --exact --accept-package-agreements --accept-source-agreements
}

function Upgrade-WingetPackage {
    param(
        [string]$Id,
        [string]$Name
    )

    Write-DotfilesLog "upgrading $Name"
    winget upgrade --id $Id --exact --accept-package-agreements --accept-source-agreements
}

function Update-WingetSources {
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
    @{ ComponentId = "package-chezmoi"; Id = "twpayne.chezmoi"; Name = "chezmoi"; Commands = @("chezmoi") },
    @{ ComponentId = "package-msys2"; Id = "MSYS2.MSYS2"; Name = "MSYS2"; Paths = @("C:\msys64\usr\bin\pacman.exe") },
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
Assert-Winget

switch ($Command) {
    "install" {
        foreach ($Package in (Select-Packages $PackageId)) {
            Install-WingetPackage -Id $Package.Id -Name $Package.Name -Commands $Package.Commands -Paths $Package.Paths
        }
        Write-DotfilesLog "Windows package setup complete"
    }
    "update" {
        Update-WingetSources
    }
    "upgrade" {
        Update-WingetSources
        foreach ($Package in (Select-Packages $PackageId)) {
            Upgrade-WingetPackage -Id $Package.Id -Name $Package.Name
        }
        Write-DotfilesLog "Windows managed package upgrade complete"
    }
}
