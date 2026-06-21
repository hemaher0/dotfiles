# Managed by chezmoi.

if [[ -n "${MSYSTEM:-}" && "${OSTYPE:-}" == cygwin* ]]; then
  # zsh-vi-mode cursor-shape detection can misparse MSYS2/Windows terminal
  # sequences. WezTerm owns the cursor style on Windows, so leave it there.
  ZVM_CURSOR_STYLE_ENABLED=false
fi
