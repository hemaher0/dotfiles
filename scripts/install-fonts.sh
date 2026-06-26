#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FONT_SOURCE_ROOT="${FONT_SOURCE_DIR:-$ROOT_DIR/assets/fonts}"
FONT_DIR="${FONT_DIR:-$HOME/.local/share/fonts/dotfiles}"

usage() {
  cat <<'EOF'
Usage: install-fonts.sh [install|update|help] [all|font-red-hat-mono|font-d2coding-ligature]

Installs the bundled terminal fonts:
  - Red Hat Mono
  - D2CodingLigature Nerd Font

On WSL, this script installs Windows fonts when possible. It also installs
Linux fontconfig fonts when WSL has a local wezterm binary or when
DOTFILES_INSTALL_WSL_LINUX_FONTS=1 is set.
EOF
}

log() {
  printf '%s\n' "dotfiles: $*"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

require_font_source() {
  font_source_dir=$1

  if [ ! -d "$font_source_dir" ]; then
    log "font source directory is not ready: $font_source_dir"
    exit 1
  fi
}

font_count() {
  font_source_dir=$1

  find "$font_source_dir" -type f \( -iname "*.ttf" -o -iname "*.otf" \) | wc -l | tr -d ' '
}

font_source_dirs() {
  case "$1" in
    ""|all)
      printf '%s\n' "$FONT_SOURCE_ROOT/RedHatMono"
      printf '%s\n' "$FONT_SOURCE_ROOT/D2Coding"
      ;;
    font-red-hat-mono|red-hat-mono|RedHatMono)
      printf '%s\n' "$FONT_SOURCE_ROOT/RedHatMono"
      ;;
    font-d2coding-ligature|d2coding-ligature|D2Coding)
      printf '%s\n' "$FONT_SOURCE_ROOT/D2Coding"
      ;;
    *)
      log "unknown font id: $1"
      exit 1
      ;;
  esac
}

copy_bundled_fonts() {
  font_source_dir=$1

  require_font_source "$font_source_dir"

  count=$(font_count "$font_source_dir")
  if [ "$count" -eq 0 ]; then
    log "no font files found in $font_source_dir"
    exit 1
  fi

  mkdir -p "$FONT_DIR"
  find "$font_source_dir" -type f \( -iname "*.ttf" -o -iname "*.otf" \) -exec cp -f {} "$FONT_DIR"/ \;
}

refresh_font_cache() {
  if has_command fc-cache; then
    if ! fc-cache -f "$FONT_DIR" >/dev/null 2>&1; then
      log "fc-cache failed; restart the terminal if fonts do not appear"
    fi
  else
    log "fc-cache was not found; restart the terminal if fonts do not appear"
  fi
}

is_wsl() {
  [ -r /proc/sys/kernel/osrelease ] && grep -qi microsoft /proc/sys/kernel/osrelease
}

install_windows_fonts_from_wsl() {
  command_name=$1
  font_id=$2

  if ! has_command powershell.exe || ! has_command wslpath; then
    log "WSL detected, but powershell.exe or wslpath is not available"
    log "run scripts/install-fonts.ps1 from Windows PowerShell instead"
    return 1
  fi

  ps_script=$(wslpath -w "$ROOT_DIR/scripts/install-fonts.ps1")
  log "installing Windows fonts through PowerShell: $ps_script"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps_script" "$command_name" "$font_id"
}

install_linux_fonts() {
  font_id=$1

  font_source_dirs "$font_id" | while IFS= read -r font_source_dir; do
    copy_bundled_fonts "$font_source_dir"
  done
  refresh_font_cache
  log "installed bundled fonts into $FONT_DIR"
}

command_name="${1:-install}"
font_id="${2:-all}"

case "$command_name" in
  install|update)
    if is_wsl; then
      installed_windows_fonts=0
      installed_linux_fonts=0

      if install_windows_fonts_from_wsl "$command_name" "$font_id"; then
        installed_windows_fonts=1
      fi

      if [ "${DOTFILES_INSTALL_WSL_LINUX_FONTS:-0}" = "1" ] || has_command wezterm; then
        install_linux_fonts "$font_id"
        installed_linux_fonts=1
      fi

      if [ "$installed_windows_fonts" -eq 0 ] && [ "$installed_linux_fonts" -eq 0 ]; then
        exit 1
      fi
    else
      install_linux_fonts "$font_id"
    fi
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
