param(
    [ValidateSet("install", "update", "sync", "clean", "help")]
    [string]$Command = "install",
    [string]$PluginId = "all"
)

$ErrorActionPreference = "Stop"

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Show-Usage {
    @"
Usage: install-neovim-plugins.ps1 [install|update|sync|clean|help] [all|plugin-nvim-<name>]

Installs or updates plugins for the default Neovim profile.
Use NVIM_APPNAME to target another profile.
"@
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Resolve-PluginName {
    param([string]$Id)

    if ([string]::IsNullOrWhiteSpace($Id) -or $Id -eq "all" -or $Id -eq "plugin-nvim") {
        return ""
    }

    $Plugins = @(
        @{ ComponentId = "plugin-nvim-lazy"; Name = "lazy.nvim" },
        @{ ComponentId = "plugin-nvim-smart-splits"; Name = "smart-splits.nvim" },
        @{ ComponentId = "plugin-nvim-blink-cmp"; Name = "blink.cmp" },
        @{ ComponentId = "plugin-nvim-neo-tree"; Name = "neo-tree.nvim" },
        @{ ComponentId = "plugin-nvim-treesitter"; Name = "nvim-treesitter" },
        @{ ComponentId = "plugin-nvim-mason"; Name = "mason.nvim" }
    )

    $Selected = @($Plugins | Where-Object { $_.ComponentId -eq $Id -or $_.Name -eq $Id })
    if ($Selected.Count -eq 0) {
        Write-DotfilesLog "unknown Neovim plugin id: $Id"
        exit 1
    }

    return $Selected[0].Name
}

function Invoke-Lazy {
    param(
        [string]$LazyCommand,
        [string]$PluginName = ""
    )

    if (-not (Test-Command "nvim")) {
        Write-DotfilesLog "nvim is required"
        exit 1
    }

    $Profile = if ($env:NVIM_APPNAME) { $env:NVIM_APPNAME } else { "nvim" }
    $ConfigDir = if ($env:DOTFILES_NVIM_CONFIG_DIR) {
        $env:DOTFILES_NVIM_CONFIG_DIR
    }
    elseif ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA $Profile
    }
    else {
        Join-Path (Join-Path $HOME ".config") $Profile
    }

    if (-not (Test-Path -Path $ConfigDir -PathType Container)) {
        Write-DotfilesLog "Neovim config directory is missing: $ConfigDir"
        exit 1
    }

    $TargetMessage = if ($PluginName) { " for $PluginName" } else { "" }
    Write-DotfilesLog "running Neovim profile '$Profile': Lazy $LazyCommand$TargetMessage"
    $PluginLua = $PluginName.Replace("\", "\\").Replace("'", "\'")
    $LuaCommand = "local command = '$LazyCommand'; local plugin = '$PluginLua'; local config_dir = vim.env.DOTFILES_NVIM_CONFIG_DIR; if config_dir and config_dir ~= '' then vim.opt.runtimepath:prepend(config_dir) end; local ok, lazy = pcall(require, 'lazy'); if not ok then local setup_ok, setup_err = pcall(require, 'user.lazy'); if not setup_ok then vim.api.nvim_err_writeln('failed to load dotfiles Neovim lazy setup: ' .. tostring(setup_err)); vim.cmd('cquit') end; ok, lazy = pcall(require, 'lazy') end; if not ok then vim.api.nvim_err_writeln('lazy.nvim is not loaded: ' .. tostring(lazy)); vim.cmd('cquit') end; local opts = { wait = true, show = false }; if plugin ~= '' then opts.plugins = { plugin } end; lazy[command](opts)"
    $PreviousNvimAppName = $env:NVIM_APPNAME
    $PreviousConfigDir = $env:DOTFILES_NVIM_CONFIG_DIR
    $env:NVIM_APPNAME = $Profile
    $env:DOTFILES_NVIM_CONFIG_DIR = $ConfigDir
    try {
        & nvim --headless "+lua $LuaCommand" "+qa"
    }
    finally {
        $env:NVIM_APPNAME = $PreviousNvimAppName
        $env:DOTFILES_NVIM_CONFIG_DIR = $PreviousConfigDir
    }
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$PluginName = Resolve-PluginName $PluginId

switch ($Command) {
    "install" { Invoke-Lazy "install" $PluginName }
    "update" { Invoke-Lazy "sync" $PluginName }
    "sync" { Invoke-Lazy "sync" $PluginName }
    "clean" { Invoke-Lazy "clean" $PluginName }
    "help" { Show-Usage }
}
