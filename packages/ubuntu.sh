#!/usr/bin/env bash
set -euo pipefail

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

install_chezmoi() {
  if has_command chezmoi || [ -x "$HOME/.local/bin/chezmoi" ]; then
    log "chezmoi is already installed"
    return
  fi

  mkdir -p "$HOME/.local/bin"
  sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$HOME/.local/bin"
}

if ! has_command apt-get; then
  log "apt-get is required for this script"
  exit 1
fi

log "updating apt package index"
as_root apt-get update

log "installing Ubuntu packages"
as_root apt-get install -y \
  bat \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  fd-find \
  fontconfig \
  fzf \
  git \
  less \
  make \
  neovim \
  openssh-client \
  pkg-config \
  python3 \
  python3-pip \
  python3-venv \
  ripgrep \
  tar \
  unzip \
  wget \
  xz-utils \
  zsh

install_chezmoi

log "Ubuntu package setup complete"
