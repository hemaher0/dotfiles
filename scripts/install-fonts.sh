#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FONT_SOURCE_DIR="${FONT_SOURCE_DIR:-$ROOT_DIR/assets/fonts}"
FONT_DIR="${FONT_DIR:-$HOME/.local/share/fonts/dotfiles}"
TERMUX_FONT_FILE="${TERMUX_FONT_FILE:-$HOME/.termux/font.ttf}"

usage() {
  cat <<'EOF'
Usage: install-fonts.sh [install|update|help]

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
  if [ ! -d "$FONT_SOURCE_DIR" ]; then
    log "font source directory is not ready: $FONT_SOURCE_DIR"
    exit 1
  fi
}

font_count() {
  find "$FONT_SOURCE_DIR" -type f \( -iname "*.ttf" -o -iname "*.otf" \) | wc -l | tr -d ' '
}

copy_bundled_fonts() {
  require_font_source

  count=$(font_count)
  if [ "$count" -eq 0 ]; then
    log "no font files found in $FONT_SOURCE_DIR"
    exit 1
  fi

  mkdir -p "$FONT_DIR"
  find "$FONT_SOURCE_DIR" -type f \( -iname "*.ttf" -o -iname "*.otf" \) -exec cp -f {} "$FONT_DIR"/ \;
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

is_termux() {
  [ -n "${PREFIX:-}" ] && has_command pkg
}

install_windows_fonts_from_wsl() {
  command_name=$1

  if ! has_command powershell.exe || ! has_command wslpath; then
    log "WSL detected, but powershell.exe or wslpath is not available"
    log "run scripts/install-fonts.ps1 from Windows PowerShell instead"
    return 1
  fi

  ps_script=$(wslpath -w "$ROOT_DIR/scripts/install-fonts.ps1")
  log "installing Windows fonts through PowerShell: $ps_script"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps_script" "$command_name"
}

install_termux_font() {
  require_font_source

  font_file="$FONT_SOURCE_DIR/D2Coding/D2CodingLigatureNerdFontMono-Regular.ttf"
  if [ ! -r "$font_file" ]; then
    font_file="$FONT_SOURCE_DIR/D2Coding/D2CodingLigatureNerdFont-Regular.ttf"
  fi

  if [ ! -r "$font_file" ]; then
    log "could not find a Termux font in $FONT_SOURCE_DIR/D2Coding"
    exit 1
  fi

  mkdir -p "$(dirname "$TERMUX_FONT_FILE")"
  cp -f "$font_file" "$TERMUX_FONT_FILE"

  if has_command termux-reload-settings; then
    termux-reload-settings
  else
    log "termux-reload-settings was not found; restart Termux if the font does not appear"
  fi

  log "installed Termux font: $TERMUX_FONT_FILE"
  log "Termux supports a single terminal font file; D2CodingLigature Nerd Font Mono is used for icon coverage"
}

install_linux_fonts() {
  copy_bundled_fonts
  refresh_font_cache
  log "installed bundled fonts into $FONT_DIR"
}

command_name="${1:-install}"

case "$command_name" in
  install|update)
    if is_wsl; then
      installed_windows_fonts=0
      installed_linux_fonts=0

      if install_windows_fonts_from_wsl "$command_name"; then
        installed_windows_fonts=1
      fi

      if [ "${DOTFILES_INSTALL_WSL_LINUX_FONTS:-0}" = "1" ] || has_command wezterm; then
        install_linux_fonts
        installed_linux_fonts=1
      fi

      if [ "$installed_windows_fonts" -eq 0 ] && [ "$installed_linux_fonts" -eq 0 ]; then
        exit 1
      fi
    elif is_termux; then
      install_termux_font
    else
      install_linux_fonts
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
