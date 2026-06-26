#!/usr/bin/env sh
set -eu

NVIM_APPNAME="${NVIM_APPNAME:-nvim}"
COMMAND="${1:-install}"
PLUGIN_ID="${2:-all}"

usage() {
  cat <<'EOF'
Usage: install-neovim-plugins.sh [install|update|sync|clean|help] [all|plugin-nvim-<name>]

Installs or updates plugins for the default Neovim profile.
Use NVIM_APPNAME to target another profile.
EOF
}

log() {
  printf '%s\n' "dotfiles: $*"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

plugin_name() {
  case "$1" in
    ""|all|plugin-nvim)
      printf '%s\n' ""
      ;;
    plugin-nvim-lazy|lazy.nvim)
      printf '%s\n' "lazy.nvim"
      ;;
    plugin-nvim-smart-splits|smart-splits.nvim)
      printf '%s\n' "smart-splits.nvim"
      ;;
    plugin-nvim-blink-cmp|blink.cmp)
      printf '%s\n' "blink.cmp"
      ;;
    plugin-nvim-neo-tree|neo-tree.nvim)
      printf '%s\n' "neo-tree.nvim"
      ;;
    plugin-nvim-treesitter|nvim-treesitter)
      printf '%s\n' "nvim-treesitter"
      ;;
    plugin-nvim-mason|mason.nvim)
      printf '%s\n' "mason.nvim"
      ;;
    *)
      log "unknown Neovim plugin id: $1"
      exit 1
      ;;
  esac
}

lua_string() {
  printf '%s' "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g"
}

run_lazy() {
  lazy_command=$1
  selected_plugin=$(plugin_name "$PLUGIN_ID")
  config_dir="${DOTFILES_NVIM_CONFIG_DIR:-$HOME/.config/$NVIM_APPNAME}"

  if ! has_command nvim; then
    log "nvim is required"
    exit 1
  fi

  if [ ! -d "$config_dir" ]; then
    log "Neovim config directory is missing: $config_dir"
    exit 1
  fi

  if [ -n "$selected_plugin" ]; then
    log "running Neovim profile '$NVIM_APPNAME': Lazy $lazy_command for $selected_plugin"
  else
    log "running Neovim profile '$NVIM_APPNAME': Lazy $lazy_command"
  fi

  selected_plugin_lua=$(lua_string "$selected_plugin")
  lua_command="local command = '$lazy_command'; local plugin = '$selected_plugin_lua'; local config_dir = vim.env.DOTFILES_NVIM_CONFIG_DIR; if config_dir and config_dir ~= '' then vim.opt.runtimepath:prepend(config_dir) end; local ok, lazy = pcall(require, 'lazy'); if not ok then local setup_ok, setup_err = pcall(require, 'user.lazy'); if not setup_ok then vim.api.nvim_err_writeln('failed to load dotfiles Neovim lazy setup: ' .. tostring(setup_err)); vim.cmd('cquit') end; ok, lazy = pcall(require, 'lazy') end; if not ok then vim.api.nvim_err_writeln('lazy.nvim is not loaded: ' .. tostring(lazy)); vim.cmd('cquit') end; local opts = { wait = true, show = false }; if plugin ~= '' then opts.plugins = { plugin } end; lazy[command](opts)"

  DOTFILES_NVIM_CONFIG_DIR="$config_dir" NVIM_APPNAME="$NVIM_APPNAME" nvim --headless \
    "+lua $lua_command" \
    "+qa"
}

case "$COMMAND" in
  install)
    run_lazy install
    ;;
  update|sync)
    run_lazy sync
    ;;
  clean)
    run_lazy clean
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
