#!/usr/bin/env sh
set -eu

log() {
  printf '%s\n' "dotfiles: $*"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

if ! has_command pkg; then
  log "pkg is required for this script"
  exit 1
fi

if [ -z "${PREFIX:-}" ]; then
  log "PREFIX is not set; this does not look like Termux"
  exit 1
fi

log "updating Termux package index"
pkg update -y

log "installing Termux packages"
pkg install -y \
  bat \
  ca-certificates \
  chezmoi \
  clang \
  cmake \
  curl \
  direnv \
  eza \
  fd \
  fzf \
  git \
  less \
  make \
  neovim \
  openssh \
  pkg-config \
  python \
  ripgrep \
  tar \
  unzip \
  wget \
  xz-utils \
  zoxide \
  zsh

log "Termux package setup complete"
