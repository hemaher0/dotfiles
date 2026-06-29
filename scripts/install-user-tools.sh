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

  if is_msys2_runtime && has_command powershell.exe && has_command cygpath; then
    output_windows=$(cygpath -w "$output")
    DOTFILES_DOWNLOAD_URL=$url DOTFILES_DOWNLOAD_OUTPUT=$output_windows powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '$ProgressPreference = "SilentlyContinue"; Invoke-WebRequest -Uri $env:DOTFILES_DOWNLOAD_URL -OutFile $env:DOTFILES_DOWNLOAD_OUTPUT'
    return
  fi

  if has_command curl && curl -fL "$url" -o "$output"; then
    return
  fi

  if has_command wget && wget -O "$output" "$url"; then
    return
  fi

  if has_command powershell.exe && has_command cygpath; then
    output_windows=$(cygpath -w "$output")
    DOTFILES_DOWNLOAD_URL=$url DOTFILES_DOWNLOAD_OUTPUT=$output_windows powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '$ProgressPreference = "SilentlyContinue"; Invoke-WebRequest -Uri $env:DOTFILES_DOWNLOAD_URL -OutFile $env:DOTFILES_DOWNLOAD_OUTPUT'
    return
  fi

  log "curl, wget, or powershell.exe is required to download user-local tools"
  exit 1
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
    MINGW*_NT*:x86_64|MSYS_NT*:x86_64|UCRT*_NT*:x86_64|CLANG*_NT*:x86_64) printf '%s\n' "direnv.windows-amd64" ;;
    MINGW*_NT*:aarch64|MINGW*_NT*:arm64|MSYS_NT*:aarch64|MSYS_NT*:arm64|UCRT*_NT*:aarch64|UCRT*_NT*:arm64|CLANG*_NT*:aarch64|CLANG*_NT*:arm64) printf '%s\n' "direnv.windows-arm64" ;;
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
    direnv)
      install_direnv
      return
      ;;
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

is_msys2_runtime() {
  command -v pacman >/dev/null 2>&1 || return 1

  case "$(uname -s)" in
    MSYS_NT*|MINGW*_NT*|UCRT*_NT*|CLANG*_NT*)
      return 0
      ;;
    *)
      return 1
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
  case "$asset" in
    direnv.windows-*)
      download "$url" "$BIN_DIR/direnv.exe"
      chmod +x "$BIN_DIR/direnv.exe"
      ;;
    *)
      download "$url" "$BIN_DIR/direnv"
      chmod +x "$BIN_DIR/direnv"
      ;;
  esac
}

command_name="${1:-install}"
tool_name="${2:-all}"

install_tools() {
  if is_msys2_runtime; then
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
