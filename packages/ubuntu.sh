#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
USER_PREFIX="${USER_PREFIX:-$HOME/.local}"
BIN_DIR="${BIN_DIR:-$USER_PREFIX/bin}"
OPT_DIR="${OPT_DIR:-$USER_PREFIX/opt}"
ZSH_VERSION="${ZSH_VERSION:-5.9.1}"
NEOVIM_VERSION="${NEOVIM_VERSION:-latest}"

case ":${PATH:-}:" in
  *":$BIN_DIR:"*) ;;
  *)
    if [ -n "${PATH:-}" ]; then
      PATH="$BIN_DIR:$PATH"
    else
      PATH="$BIN_DIR"
    fi
    export PATH
    ;;
esac

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
Usage: ubuntu.sh [install|update|upgrade|user|help]

Commands:
  install  Update the apt index and install baseline packages
  update   Update the apt package index
  upgrade  Upgrade installed baseline packages only
  user     Install supported components into the user profile without apt
EOF
}

log() {
  printf '%s\n' "dotfiles: $*"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

download() {
  url=$1
  output=$2

  if has_command curl; then
    curl -fL "$url" -o "$output"
  elif has_command wget; then
    wget -O "$output" "$url"
  else
    log "curl or wget is required for downloads"
    exit 1
  fi
}

download_first() {
  output=$1
  shift

  if ! has_command curl && ! has_command wget; then
    log "curl or wget is required for downloads"
    exit 1
  fi

  for url in "$@"; do
    log "downloading $url"

    if has_command curl; then
      if curl -fL "$url" -o "$output"; then
        return 0
      fi
    elif wget -O "$output" "$url"; then
      return 0
    fi

    rm -f "$output"
  done

  log "all download URLs failed"
  exit 1
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif has_command sudo; then
    sudo "$@"
  else
    log "sudo is required for apt operations"
    log "without sudo, run: bin/dot install --user"
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
  if has_command chezmoi || [ -x "$BIN_DIR/chezmoi" ]; then
    log "chezmoi is already installed"
    return
  fi

  mkdir -p "$BIN_DIR"

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-chezmoi.XXXXXX")
  installer="$tmp_dir/install-chezmoi.sh"

  (
    trap 'rm -rf "$tmp_dir"' EXIT
    download "https://get.chezmoi.io" "$installer"
    sh "$installer" -b "$BIN_DIR"
  )
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

compile_jobs() {
  if has_command getconf; then
    jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
    if [ -n "$jobs" ] && [ "$jobs" -gt 0 ] 2>/dev/null; then
      printf '%s\n' "$jobs"
      return
    fi
  fi

  printf '%s\n' "2"
}

has_c_compiler() {
  has_command cc || has_command gcc || has_command clang
}

require_compile_commands() {
  missing=0

  for command_name in "$@"; do
    if ! has_command "$command_name"; then
      log "$command_name is required to compile zsh"
      missing=1
    fi
  done

  if ! has_c_compiler; then
    log "a C compiler is required to compile zsh"
    missing=1
  fi

  if [ "$missing" -ne 0 ]; then
    log "install compiler prerequisites first, or use the normal apt path with sudo"
    exit 1
  fi
}

should_install_command() {
  command_name=$1

  if [ "${DOTFILES_FORCE_USER_INSTALL:-0}" = "1" ]; then
    return 0
  fi

  ! has_command "$command_name"
}

install_user_tools() {
  BIN_DIR="$BIN_DIR" "$ROOT_DIR/scripts/install-user-tools.sh" install
}

install_zsh_release() {
  if ! should_install_command zsh; then
    log "zsh is already available"
    return
  fi

  require_compile_commands make tar xz

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-zsh.XXXXXX")
  archive="$tmp_dir/zsh-$ZSH_VERSION.tar.xz"
  urls=(
    "https://www.zsh.org/pub/zsh-$ZSH_VERSION.tar.xz"
    "https://www.zsh.org/pub/old/zsh-$ZSH_VERSION.tar.xz"
    "https://sourceforge.net/projects/zsh/files/zsh/$ZSH_VERSION/zsh-$ZSH_VERSION.tar.xz/download"
  )

  log "installing zsh $ZSH_VERSION stable release into $USER_PREFIX"
  (
    trap 'rm -rf "$tmp_dir"' EXIT
    download_first "$archive" "${urls[@]}"
    tar -xJf "$archive" -C "$tmp_dir"
    cd "$tmp_dir/zsh-$ZSH_VERSION"
    ./configure --prefix="$USER_PREFIX"
    make -j"$(compile_jobs)"
    make install
  )
}

neovim_archive_name() {
  arch=$(uname -m)

  case "$arch" in
    x86_64|amd64) printf '%s\n' "nvim-linux-x86_64" ;;
    aarch64|arm64) printf '%s\n' "nvim-linux-arm64" ;;
    *)
      log "unsupported Neovim binary architecture: $arch"
      exit 1
      ;;
  esac
}

neovim_download_url() {
  archive_name=$1

  if [ "$NEOVIM_VERSION" = "latest" ]; then
    printf '%s\n' "https://github.com/neovim/neovim/releases/latest/download/$archive_name.tar.gz"
  else
    printf '%s\n' "https://github.com/neovim/neovim/releases/download/$NEOVIM_VERSION/$archive_name.tar.gz"
  fi
}

install_neovim_binary() {
  if ! should_install_command nvim; then
    log "nvim is already available"
    return
  fi

  if ! has_command tar; then
    log "tar is required to install the Neovim binary archive"
    exit 1
  fi

  archive_name=$(neovim_archive_name)
  url=$(neovim_download_url "$archive_name")
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-nvim.XXXXXX")
  archive="$tmp_dir/$archive_name.tar.gz"
  install_dir="$OPT_DIR/$archive_name"

  log "installing Neovim $NEOVIM_VERSION binary into $install_dir"
  (
    trap 'rm -rf "$tmp_dir"' EXIT
    download "$url" "$archive"
    tar -xzf "$archive" -C "$tmp_dir"
    mkdir -p "$OPT_DIR" "$BIN_DIR"
    rm -rf "$install_dir"
    mv "$tmp_dir/$archive_name" "$install_dir"
    ln -sfn "$install_dir/bin/nvim" "$BIN_DIR/nvim"
  )
}

install_user_setup() {
  mkdir -p "$BIN_DIR" "$OPT_DIR"

  install_chezmoi
  install_user_tools
  install_zsh_release
  install_neovim_binary

  log "Ubuntu user-local setup complete"
  log "ensure $BIN_DIR is on PATH"
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
  user)
    install_user_setup
    ;;
  *)
    usage
    exit 1
    ;;
esac
