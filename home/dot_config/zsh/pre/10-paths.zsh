# Managed by chezmoi.

typeset -U path PATH

prepend_path() {
  [[ -d "$1" ]] && path=("$1" "${path[@]}")
}

prepend_path "$HOME/.local/bin"
prepend_path "$HOME/bin"
prepend_path "$HOME/neovim/bin"
prepend_path "$HOME/.cargo/bin"
prepend_path "$HOME/.local/share/mise/shims"
prepend_path "$HOME/.bun/bin"

if [[ -n "${PREFIX:-}" ]]; then
  prepend_path "$PREFIX/bin"
fi

if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
  prepend_path "/clang64/bin"
  prepend_path "/mingw64/bin"
  prepend_path "/ucrt64/bin"

  append_path() {
    [[ -d "$1" ]] && path+=("$1")
  }

  append_path "/usr/bin"
  append_path "/bin"
  unset -f append_path
fi

prepend_path "/opt/nvim-linux-x86_64/bin"
prepend_path "/opt/nvim/bin"

export PATH
unset -f prepend_path
