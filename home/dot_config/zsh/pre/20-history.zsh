# Managed by chezmoi.

export HISTFILE="${HISTFILE:-$ZSH_CACHE_DIR/history}"
export HISTSIZE="${HISTSIZE:-100000}"
export SAVEHIST="${SAVEHIST:-100000}"

mkdir -p "${HISTFILE:h}"

setopt append_history
setopt extended_history
setopt hist_ignore_all_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt inc_append_history
setopt share_history
