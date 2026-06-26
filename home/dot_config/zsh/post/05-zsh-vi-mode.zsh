# Managed by chezmoi.

# zsh-vi-mode's default cursor reset (`ud`) currently trips a zsh regex bug in
# MSYS2/Cygwin: "zvm_cursor_style: failed to compile regex: trailing backslash".
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
  ZVM_CURSOR_STYLE_ENABLED=false

  if (( $+functions[zvm_zle-line-finish] )); then
    function zvm_zle-line-finish() {
      if ${ZVM_CURSOR_STYLE_ENABLED:-true}; then
        local shape
        shape=$(zvm_cursor_style "$ZVM_CURSOR_USER_DEFAULT")
        zvm_set_cursor "$shape"
      fi

      zvm_switch_keyword_history=()
    }
  fi
fi
