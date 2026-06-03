# Managed by chezmoi.

if command -v nvim >/dev/null 2>&1; then
  export EDITOR="${EDITOR:-nvim}"
  export VISUAL="${VISUAL:-nvim}"
else
  export EDITOR="${EDITOR:-vi}"
  export VISUAL="${VISUAL:-$EDITOR}"
fi

export PAGER="${PAGER:-less}"
export LESS="${LESS:--FRX}"
