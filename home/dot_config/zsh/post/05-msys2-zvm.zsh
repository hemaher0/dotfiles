# Managed by chezmoi.

if [[ -n "${MSYSTEM:-}" && "${OSTYPE:-}" == cygwin* ]]; then
  # zsh-vi-mode calls this from zle-line-finish even when cursor style updates
  # are disabled. MSYS2 zsh's regex engine rejects the plugin's reset regex, so
  # make cursor-shape changes a no-op and let WezTerm manage the cursor.
  function zvm_cursor_style() {
    return 0
  }
fi
