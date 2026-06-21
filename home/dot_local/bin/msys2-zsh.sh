#!/usr/bin/env sh
set -eu

windows_home=$(cygpath -u "${USERPROFILE:-$HOME}")
export HOME="$windows_home"
export ZDOTDIR="$windows_home"
export MSYSTEM="${MSYSTEM:-MSYS}"
export CHERE_INVOKING=1

cd "$HOME"
exec /usr/bin/zsh "$@"
