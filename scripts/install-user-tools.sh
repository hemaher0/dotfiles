#!/usr/bin/env sh
set -eu

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
ZOXIDE_VERSION="${ZOXIDE_VERSION:-0.9.9}"
DIRENV_VERSION="${DIRENV_VERSION:-2.37.1}"

usage() {
  cat <<'EOF'
Usage: install-user-tools.sh [install|update] [all|zoxide|direnv]

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

msys2_package_prefix() {
  case "${MSYSTEM:-UCRT64}" in
    UCRT64) printf '%s\n' "mingw-w64-ucrt-x86_64" ;;
    MINGW64) printf '%s\n' "mingw-w64-x86_64" ;;
    CLANG64) printf '%s\n' "mingw-w64-clang-x86_64" ;;
    *)
      log "unsupported MSYS2 environment: ${MSYSTEM:-unset}"
      exit 1
      ;;
  esac
}

install_msys2_tool() {
  package_prefix=$(msys2_package_prefix)

  case "$1" in
    zoxide) package_name="$package_prefix-zoxide" ;;
    direnv) package_name="$package_prefix-direnv" ;;
    *)
      usage
      exit 1
      ;;
  esac

  log "installing MSYS2 package $package_name"
  pacman -Sy --needed --noconfirm "$package_name"
}

install_msys2_tools() {
  case "$tool_name" in
    all)
      install_msys2_tool zoxide
      install_msys2_tool direnv
      ;;
    zoxide|direnv)
      install_msys2_tool "$tool_name"
      ;;
    *)
      usage
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
tool_name="${2:-all}"

install_tools() {
  if command -v pacman >/dev/null 2>&1 && uname -s | grep -Eq '^(MSYS|MINGW|UCRT|CLANG)_NT'; then
    install_msys2_tools
    return
  fi

  case "$tool_name" in
    all)
      install_zoxide
      install_direnv
      ;;
    zoxide)
      install_zoxide
      ;;
    direnv)
      install_direnv
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

case "$command_name" in
  install|update)
    install_tools
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
