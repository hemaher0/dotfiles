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
    @{ ComponentId = "package-git"; Id = "Git.Git"; Name = "Git" },
    @{ ComponentId = "package-chezmoi"; Id = "twpayne.chezmoi"; Name = "chezmoi" },
    @{ ComponentId = "package-nvim"; Id = "Neovim.Neovim"; Name = "Neovim" },
    @{ ComponentId = "package-wezterm"; Id = "wez.wezterm"; Name = "WezTerm" },
    @{ ComponentId = "package-ripgrep"; Id = "BurntSushi.ripgrep.MSVC"; Name = "ripgrep" },
    @{ ComponentId = "package-fd"; Id = "sharkdp.fd"; Name = "fd" },
    @{ ComponentId = "package-fzf"; Id = "junegunn.fzf"; Name = "fzf" },
    @{ ComponentId = "package-eza"; Id = "eza-community.eza"; Name = "eza" },
    @{ ComponentId = "dependency-rust"; Id = "Rustlang.Rustup"; Name = "Rustup" },
    @{ ComponentId = "package-pwsh"; Id = "Microsoft.PowerShell"; Name = "PowerShell" }
)

if ($Command -eq "help") {
    Show-Usage
    exit 0
}

Assert-Winget

switch ($Command) {
    "install" {
        foreach ($Package in (Select-Packages $PackageId)) {
            Install-WingetPackage -Id $Package.Id -Name $Package.Name
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
