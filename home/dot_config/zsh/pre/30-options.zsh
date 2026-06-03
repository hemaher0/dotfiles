# Managed by chezmoi.

setopt always_to_end
setopt auto_cd
setopt auto_pushd
setopt complete_in_word
setopt interactive_comments
setopt no_beep
setopt prompt_subst
setopt pushd_ignore_dups

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z} r:|[._-]=* r:|=*'
