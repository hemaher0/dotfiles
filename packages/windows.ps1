$ErrorActionPreference = "Stop"

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
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

if (-not (Test-Command "winget")) {
    Write-DotfilesLog "winget is required for this script"
    exit 1
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
    @{ Id = "Microsoft.PowerShell"; Name = "PowerShell" }
)

foreach ($Package in $Packages) {
    Install-WingetPackage -Id $Package.Id -Name $Package.Name
}

Write-DotfilesLog "Windows package setup complete"
