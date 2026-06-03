#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

log() {
  printf '%s\n' "dotfiles: $*"
}

if [ ! -r /proc/sys/kernel/osrelease ] || ! grep -qi microsoft /proc/sys/kernel/osrelease; then
  log "this does not look like WSL"
  exit 1
fi

"$ROOT_DIR/packages/ubuntu.sh" "$@"

log "WSL package setup complete"
