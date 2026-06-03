#!/usr/bin/env sh
set -eu

OH_MY_TMUX_DIR="${OH_MY_TMUX_DIR:-$HOME/.local/share/oh-my-tmux}"
OH_MY_TMUX_REPO="${OH_MY_TMUX_REPO:-https://github.com/gpakosz/.tmux.git}"
COMMAND="${1:-install}"

usage() {
  cat <<'EOF'
Usage: install-tmux-config.sh [install|update|help]

Installs or updates the Oh my tmux checkout used by the managed tmux config.
EOF
}

log() {
  printf '%s\n' "dotfiles: $*"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

require_git() {
  if ! has_command git; then
    log "git is required to install Oh my tmux"
    exit 1
  fi
}

update_checkout() {
  if [ ! -d "$OH_MY_TMUX_DIR/.git" ]; then
    log "Oh my tmux is not a git checkout: $OH_MY_TMUX_DIR"
    exit 1
  fi

  log "updating Oh my tmux: $OH_MY_TMUX_DIR"
  git -C "$OH_MY_TMUX_DIR" pull --ff-only
}

install_checkout() {
  if [ -d "$OH_MY_TMUX_DIR/.git" ]; then
    update_checkout
    return
  fi

  if [ -e "$OH_MY_TMUX_DIR" ]; then
    log "target already exists and is not a git checkout: $OH_MY_TMUX_DIR"
    exit 1
  fi

  mkdir -p "$(dirname "$OH_MY_TMUX_DIR")"
  log "cloning Oh my tmux into $OH_MY_TMUX_DIR"
  git clone --single-branch "$OH_MY_TMUX_REPO" "$OH_MY_TMUX_DIR"
}

require_git

case "$COMMAND" in
  install)
    install_checkout
    ;;
  update)
    update_checkout
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
