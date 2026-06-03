param(
    [ValidateSet("install", "update", "help")]
    [string]$Command = "install"
)

$ErrorActionPreference = "Stop"

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Show-Usage {
    @"
Usage: install-user-tools.ps1 [install|update|help]

Installs prebuilt user-local CLI tools:
  - zoxide
  - direnv
"@
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Name
    )

    Write-DotfilesLog "installing $Name"
    winget install --id $Id --exact --accept-package-agreements --accept-source-agreements
}

if ($Command -eq "help") {
    Show-Usage
    exit 0
}

if (-not (Test-Command "winget")) {
    Write-DotfilesLog "winget is required for Windows user-local tools"
    exit 1
}

$Packages = @(
    @{ Id = "ajeetdsouza.zoxide"; Name = "zoxide" },
    @{ Id = "direnv.direnv"; Name = "direnv" }
)

foreach ($Package in $Packages) {
    Install-WingetPackage -Id $Package.Id -Name $Package.Name
}

Write-DotfilesLog "Windows user-local tool setup complete"
