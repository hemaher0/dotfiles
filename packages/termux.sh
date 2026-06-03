#!/usr/bin/env sh
set -eu

PACKAGES="
bat
ca-certificates
chezmoi
clang
cmake
curl
direnv
eza
fd
fzf
git
less
make
neovim
openssh
pkg-config
python
ripgrep
tar
unzip
wget
xz-utils
zoxide
zsh
"

usage() {
  cat <<'EOF'
Usage: termux.sh [install|update|upgrade|help]

Commands:
  install  Update the Termux package index and install baseline packages
  update   Update the Termux package index
  upgrade  Upgrade managed baseline packages without running a full pkg upgrade
EOF
}

log() {
  printf '%s\n' "dotfiles: $*"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

require_termux() {
  if ! has_command pkg; then
    log "pkg is required for this script"
    exit 1
  fi

  if [ -z "${PREFIX:-}" ]; then
    log "PREFIX is not set; this does not look like Termux"
    exit 1
  fi
}

update_package_index() {
  log "updating Termux package index"
  pkg update -y
}

install_packages() {
  update_package_index

  log "installing Termux packages"
  # shellcheck disable=SC2086
  pkg install -y $PACKAGES

  log "Termux package setup complete"
}

upgrade_packages() {
  update_package_index

  log "upgrading managed Termux packages"
  # shellcheck disable=SC2086
  pkg install -y $PACKAGES
}

command_name="${1:-install}"

if [ "$command_name" = "help" ] || [ "$command_name" = "-h" ] || [ "$command_name" = "--help" ]; then
  usage
  exit 0
fi

case "$command_name" in
  install)
    require_termux
    install_packages
    ;;
  update)
    require_termux
    update_package_index
    ;;
  upgrade)
    require_termux
    upgrade_packages
    ;;
  *)
    usage
    exit 1
    ;;
esac
