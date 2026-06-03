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
    $LuaCommand = "local ok, lazy = pcall(require, 'lazy'); if not ok then vim.api.nvim_err_writeln('lazy.nvim is not loaded: ' .. tostring(lazy)); vim.cmd('cquit') end; lazy.$LazyCommand({ wait = true, show = false })"
    $PreviousNvimAppName = $env:NVIM_APPNAME
    $env:NVIM_APPNAME = $Profile
    try {
        & nvim --headless "+lua $LuaCommand" "+qa"
    }
    finally {
        $env:NVIM_APPNAME = $PreviousNvimAppName
    }
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
