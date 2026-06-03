#!/usr/bin/env sh
set -eu

NVIM_APPNAME="${NVIM_APPNAME:-nvim}"
COMMAND="${1:-install}"

usage() {
  cat <<'EOF'
Usage: install-neovim-plugins.sh [install|update|sync|clean|help]

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

run_lazy() {
  lazy_command=$1
  config_dir="${DOTFILES_NVIM_CONFIG_DIR:-$HOME/.config/$NVIM_APPNAME}"

  if ! has_command nvim; then
    log "nvim is required"
    exit 1
  fi

  if [ ! -d "$config_dir" ]; then
    log "Neovim config directory is missing: $config_dir"
    exit 1
  fi

  log "running Neovim profile '$NVIM_APPNAME': Lazy $lazy_command"
  lua_command="local command = '$lazy_command'; local config_dir = vim.env.DOTFILES_NVIM_CONFIG_DIR; if config_dir and config_dir ~= '' then vim.opt.runtimepath:prepend(config_dir) end; local ok, lazy = pcall(require, 'lazy'); if not ok then local setup_ok, setup_err = pcall(require, 'user.lazy'); if not setup_ok then vim.api.nvim_err_writeln('failed to load dotfiles Neovim lazy setup: ' .. tostring(setup_err)); vim.cmd('cquit') end; ok, lazy = pcall(require, 'lazy') end; if not ok then vim.api.nvim_err_writeln('lazy.nvim is not loaded: ' .. tostring(lazy)); vim.cmd('cquit') end; lazy[command]({ wait = true, show = false })"

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
