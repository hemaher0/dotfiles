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

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Name
    )

    Write-DotfilesLog "installing $Name"
    winget install --id $Id --exact --accept-package-agreements --accept-source-agreements
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

if (-not (Test-Command "winget")) {
    Write-DotfilesLog "winget is required for Windows user-local tools"
    exit 1
}

$Packages = @(
    @{ ComponentId = "tool-zoxide"; Id = "ajeetdsouza.zoxide"; Name = "zoxide" },
    @{ ComponentId = "tool-direnv"; Id = "direnv.direnv"; Name = "direnv" }
)

foreach ($Package in (Select-Packages $ToolId)) {
    Install-WingetPackage -Id $Package.Id -Name $Package.Name
}

Write-DotfilesLog "Windows user-local tool setup complete"
