param(
    [ValidateSet("install", "update", "upgrade", "help")]
    [string]$Command = "install"
)

$ErrorActionPreference = "Stop"

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Show-Usage {
    @"
Usage: windows.ps1 [install|update|upgrade|help]

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

function Assert-Winget {
    if (-not (Test-Command "winget")) {
        Write-DotfilesLog "winget is required for this script"
        exit 1
    }
}

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Name
    )

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

$Packages = @(
    @{ Id = "Git.Git"; Name = "Git" },
    @{ Id = "twpayne.chezmoi"; Name = "chezmoi" },
    @{ Id = "Neovim.Neovim"; Name = "Neovim" },
    @{ Id = "wez.wezterm"; Name = "WezTerm" },
    @{ Id = "BurntSushi.ripgrep.MSVC"; Name = "ripgrep" },
    @{ Id = "sharkdp.fd"; Name = "fd" },
    @{ Id = "junegunn.fzf"; Name = "fzf" },
    @{ Id = "eza-community.eza"; Name = "eza" },
    @{ Id = "Rustlang.Rustup"; Name = "Rustup" },
    @{ Id = "Microsoft.PowerShell"; Name = "PowerShell" }
)

if ($Command -eq "help") {
    Show-Usage
    exit 0
}

Assert-Winget

switch ($Command) {
    "install" {
        foreach ($Package in $Packages) {
            Install-WingetPackage -Id $Package.Id -Name $Package.Name
        }
        Write-DotfilesLog "Windows package setup complete"
    }
    "update" {
        Update-WingetSources
    }
    "upgrade" {
        Update-WingetSources
        foreach ($Package in $Packages) {
            Upgrade-WingetPackage -Id $Package.Id -Name $Package.Name
        }
        Write-DotfilesLog "Windows managed package upgrade complete"
    }
}
