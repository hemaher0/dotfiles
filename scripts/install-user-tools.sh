#!/usr/bin/env sh
set -eu

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
ZOXIDE_VERSION="${ZOXIDE_VERSION:-0.9.9}"
DIRENV_VERSION="${DIRENV_VERSION:-2.37.1}"

usage() {
  cat <<'EOF'
Usage: install-user-tools.sh [install|update|help]

Installs prebuilt user-local CLI tools into ${BIN_DIR:-$HOME/.local/bin}:
  - zoxide
  - direnv
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
    log "curl or wget is required to download user-local tools"
    exit 1
  fi
}

zoxide_target() {
  os=$(uname -s)
  arch=$(uname -m)

  case "$os:$arch" in
    Linux:x86_64) printf '%s\n' "x86_64-unknown-linux-musl" ;;
    Linux:aarch64|Linux:arm64) printf '%s\n' "aarch64-unknown-linux-musl" ;;
    *)
      log "unsupported zoxide platform: $os $arch"
      exit 1
      ;;
  esac
}

direnv_asset() {
  os=$(uname -s)
  arch=$(uname -m)

  case "$os:$arch" in
    Linux:x86_64) printf '%s\n' "direnv.linux-amd64" ;;
    Linux:aarch64|Linux:arm64) printf '%s\n' "direnv.linux-arm64" ;;
    *)
      log "unsupported direnv platform: $os $arch"
      exit 1
      ;;
  esac
}

install_zoxide() {
  target=$(zoxide_target)
  tmp_dir=$(mktemp -d)
  archive="$tmp_dir/zoxide.tar.gz"
  url="https://github.com/ajeetdsouza/zoxide/releases/download/v$ZOXIDE_VERSION/zoxide-$ZOXIDE_VERSION-$target.tar.gz"

  log "installing zoxide $ZOXIDE_VERSION"
  download "$url" "$archive"
  tar -xzf "$archive" -C "$tmp_dir"

  binary=$(find "$tmp_dir" -type f -name zoxide | sort | sed -n '1p')
  if [ -z "$binary" ]; then
    log "could not find zoxide binary in release archive"
    rm -rf "$tmp_dir"
    exit 1
  fi

  mkdir -p "$BIN_DIR"
  cp -f "$binary" "$BIN_DIR/zoxide"
  chmod +x "$BIN_DIR/zoxide"
  rm -rf "$tmp_dir"
}

install_direnv() {
  asset=$(direnv_asset)
  url="https://github.com/direnv/direnv/releases/download/v$DIRENV_VERSION/$asset"

  log "installing direnv $DIRENV_VERSION"
  mkdir -p "$BIN_DIR"
  download "$url" "$BIN_DIR/direnv"
  chmod +x "$BIN_DIR/direnv"
}

command_name="${1:-install}"

case "$command_name" in
  install|update)
    install_zoxide
    install_direnv
    log "installed user-local tools into $BIN_DIR"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
