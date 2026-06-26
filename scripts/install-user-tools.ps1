param(
    [ValidateSet("install", "update", "help")]
    [string]$Command = "install",
    [string]$ToolId = "all"
)

$ErrorActionPreference = "Stop"

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Show-Usage {
    @"
Usage: install-user-tools.ps1 [install|update|help] [all|zoxide|direnv|tool-zoxide|tool-direnv]

Installs prebuilt user-local CLI tools:
  - zoxide
  - direnv
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

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Name,
        [string]$CommandName
    )

    if (Test-Command $CommandName) {
        Write-DotfilesLog "already installed: $Name"
        return
    }

    Write-DotfilesLog "installing $Name"
    winget install --id $Id --exact --accept-package-agreements --accept-source-agreements
    Update-ProcessPath
}

function Select-Packages {
    param([string]$Id)

    if ([string]::IsNullOrWhiteSpace($Id) -or $Id -eq "all") {
        return $Packages
    }

    $Selected = @($Packages | Where-Object { $_.ComponentId -eq $Id -or $_.Id -eq $Id -or $_.Name -eq $Id })
    if ($Selected.Count -eq 0) {
        Write-DotfilesLog "unknown Windows user tool id: $Id"
        exit 1
    }

    return $Selected
}

if ($Command -eq "help") {
    Show-Usage
    exit 0
}

Update-ProcessPath

if (-not (Test-Command "winget")) {
    Write-DotfilesLog "winget is required for Windows user-local tools"
    exit 1
}

$Packages = @(
    @{ ComponentId = "tool-zoxide"; Id = "ajeetdsouza.zoxide"; Name = "zoxide"; CommandName = "zoxide" },
    @{ ComponentId = "tool-direnv"; Id = "direnv.direnv"; Name = "direnv"; CommandName = "direnv" }
)

foreach ($Package in (Select-Packages $ToolId)) {
    Install-WingetPackage -Id $Package.Id -Name $Package.Name -CommandName $Package.CommandName
}

Write-DotfilesLog "Windows user-local tool setup complete"
