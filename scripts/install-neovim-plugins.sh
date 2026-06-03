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

  if ! has_command nvim; then
    log "nvim is required"
    exit 1
  fi

  log "running Neovim profile '$NVIM_APPNAME': Lazy $lazy_command"
  NVIM_APPNAME="$NVIM_APPNAME" nvim --headless "+Lazy! $lazy_command" "+qa"
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
