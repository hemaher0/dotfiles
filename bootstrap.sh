#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_DIR="${DOTFILES_SOURCE_DIR:-$ROOT_DIR/home}"
DOT_BIN="$ROOT_DIR/bin/dot"

log() {
  printf '%s\n' "dotfiles: $*"
}

main() {
  log "starting bootstrap"

  if [ ! -r "$DOT_BIN" ]; then
    log "dot command is missing: $DOT_BIN"
    exit 1
  fi

  if [ ! -d "$SOURCE_DIR" ]; then
    log "chezmoi source directory is not ready: $SOURCE_DIR"
    log "nothing to sync yet"
    exit 0
  fi

  DOTFILES_SOURCE_DIR="$SOURCE_DIR" sh "$DOT_BIN" install "$@"
}

main "$@"
