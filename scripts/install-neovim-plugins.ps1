param(
    [ValidateSet("install", "update", "sync", "clean", "help")]
    [string]$Command = "install"
)

$ErrorActionPreference = "Stop"

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Show-Usage {
    @"
Usage: install-neovim-plugins.ps1 [install|update|sync|clean|help]

Installs or updates plugins for the default Neovim profile.
Use NVIM_APPNAME to target another profile.
"@
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Lazy {
    param([string]$LazyCommand)

    if (-not (Test-Command "nvim")) {
        Write-DotfilesLog "nvim is required"
        exit 1
    }

    $Profile = if ($env:NVIM_APPNAME) { $env:NVIM_APPNAME } else { "nvim" }
    Write-DotfilesLog "running Neovim profile '$Profile': Lazy $LazyCommand"
    & nvim --headless "+Lazy! $LazyCommand" "+qa"
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

switch ($Command) {
    "install" { Invoke-Lazy "install" }
    "update" { Invoke-Lazy "sync" }
    "sync" { Invoke-Lazy "sync" }
    "clean" { Invoke-Lazy "clean" }
    "help" { Show-Usage }
}
