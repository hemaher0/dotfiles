# Managed by chezmoi.

alias c='clear'
alias h='history'
alias mkdir='mkdir -p'
alias zreload='source ~/.zshrc'

if command -v nvim >/dev/null 2>&1; then
  alias vi='nvim'
  alias vim='nvim'
fi

if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first'
  alias ll='eza -la --group-directories-first'
  alias la='eza -a --group-directories-first'
elif command -v exa >/dev/null 2>&1; then
  alias ls='exa --group-directories-first'
  alias ll='exa -la --group-directories-first'
  alias la='exa -a --group-directories-first'
else
  alias ll='ls -alF'
  alias la='ls -A'
  alias l='ls -CF'
fi
