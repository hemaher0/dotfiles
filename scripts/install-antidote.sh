#!/usr/bin/env sh
set -eu

ANTIDOTE_DIR="${ANTIDOTE_DIR:-${ZDOTDIR:-$HOME}/.antidote}"
ANTIDOTE_REPO="${ANTIDOTE_REPO:-https://github.com/mattmc3/antidote.git}"
ANTIDOTE_SCRIPT="${ANTIDOTE_SCRIPT:-$ANTIDOTE_DIR/antidote.zsh}"
ANTIDOTE_HOME="${ANTIDOTE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/antidote}"
ZSH_PLUGIN_FILE="${ZSH_PLUGIN_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh/plugins.txt}"
COMMAND="${1:-install}"

log() {
  printf '%s\n' "dotfiles: $*"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

usage() {
  cat <<'EOF'
Usage: install-antidote.sh [install|update]

Commands:
  install  Clone Antidote if missing, otherwise update it
  update   Update Antidote and cloned bundles
EOF
}

require_git() {
  if ! has_command git; then
    log "git is required to install Antidote"
    exit 1
  fi
}

update_antidote_checkout() {
  if [ ! -d "$ANTIDOTE_DIR/.git" ]; then
    log "Antidote is not a git checkout: $ANTIDOTE_DIR"
    exit 1
  fi

  log "updating Antidote: $ANTIDOTE_DIR"
  git -C "$ANTIDOTE_DIR" pull --ff-only
}

install_antidote() {
  if [ -d "$ANTIDOTE_DIR/.git" ]; then
    update_antidote_checkout
    return
  fi

  if [ -e "$ANTIDOTE_DIR" ]; then
    log "target already exists and is not a git checkout: $ANTIDOTE_DIR"
    exit 1
  fi

  log "cloning Antidote into $ANTIDOTE_DIR"
  git clone --depth=1 "$ANTIDOTE_REPO" "$ANTIDOTE_DIR"
}

update_bundles() {
  if ! has_command zsh; then
    log "zsh is required to update Antidote bundles"
    exit 1
  fi

  if [ ! -r "$ANTIDOTE_SCRIPT" ]; then
    log "Antidote script is missing: $ANTIDOTE_SCRIPT"
    exit 1
  fi

  if [ ! -r "$ZSH_PLUGIN_FILE" ]; then
    log "zsh plugin manifest is missing: $ZSH_PLUGIN_FILE"
    exit 1
  fi

  log "updating Antidote bundles from $ZSH_PLUGIN_FILE"
  ANTIDOTE_HOME="$ANTIDOTE_HOME" ZSH_PLUGIN_FILE="$ZSH_PLUGIN_FILE" zsh -fc '
    source "$1"
    antidote load "$ZSH_PLUGIN_FILE"
    antidote update
  ' -- "$ANTIDOTE_SCRIPT"
}

require_git

case "$COMMAND" in
  install)
    install_antidote
    ;;
  update)
    update_antidote_checkout
    update_bundles
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
