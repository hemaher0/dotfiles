#!/usr/bin/env bash
set -euo pipefail

PACKAGES=(
  bat
  build-essential
  ca-certificates
  cmake
  curl
  fd-find
  fontconfig
  fzf
  git
  less
  make
  neovim
  openssh-client
  pkg-config
  python3
  python3-pip
  python3-venv
  ripgrep
  tar
  unzip
  wget
  xz-utils
  zsh
)

usage() {
  cat <<'EOF'
Usage: ubuntu.sh [install|update|upgrade|help]

Commands:
  install  Update the apt index and install baseline packages
  update   Update the apt package index
  upgrade  Upgrade installed baseline packages only
EOF
}

log() {
  printf '%s\n' "dotfiles: $*"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif has_command sudo; then
    sudo "$@"
  else
    log "sudo is required for apt operations"
    exit 1
  fi
}

require_apt() {
  if ! has_command apt-get; then
    log "apt-get is required for this script"
    exit 1
  fi
}

update_package_index() {
  log "updating apt package index"
  as_root apt-get update
}

install_chezmoi() {
  if has_command chezmoi || [ -x "$HOME/.local/bin/chezmoi" ]; then
    log "chezmoi is already installed"
    return
  fi

  mkdir -p "$HOME/.local/bin"
  sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$HOME/.local/bin"
}

install_packages() {
  update_package_index

  log "installing Ubuntu packages"
  as_root apt-get install -y "${PACKAGES[@]}"

  install_chezmoi
  log "Ubuntu package setup complete"
}

upgrade_packages() {
  update_package_index

  log "upgrading installed Ubuntu baseline packages"
  as_root apt-get install -y --only-upgrade "${PACKAGES[@]}"
}

command_name="${1:-install}"

if [ "$command_name" = "help" ] || [ "$command_name" = "-h" ] || [ "$command_name" = "--help" ]; then
  usage
  exit 0
fi

case "$command_name" in
  install)
    require_apt
    install_packages
    ;;
  update)
    require_apt
    update_package_index
    ;;
  upgrade)
    require_apt
    upgrade_packages
    ;;
  *)
    usage
    exit 1
    ;;
esac
