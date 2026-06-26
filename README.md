# Dotfiles

Personal dotfiles for rebuilding my shell, editor, terminal, and tmux setup across Linux, WSL, and Windows.

This repository uses `chezmoi` for managed home-directory files and small wrapper scripts for repeatable setup tasks. The scripts are intentionally part of the dotfiles rather than a general-purpose installer.

## Included

- zsh configuration with Antidote-managed plugins
- Powerlevel10k prompt configuration
- Neovim and nvim-lite configuration
- tmux configuration with Oh my tmux
- WezTerm configuration
- Bundled Red Hat Mono and D2CodingLigature Nerd Font files
- zoxide and direnv setup helpers
- Platform setup scripts for Ubuntu, WSL, and Windows

## Layout

- `home/` is the chezmoi source directory.
- `bin/` contains the main dotfiles command wrappers.
- `packages/` contains platform package setup scripts.
- `scripts/` contains focused installers for fonts, plugins, and user tools.
- `assets/` contains bundled local assets such as fonts.
- `tools/` contains helper applications used by the dotfiles workflow.

## Windows Notes

Windows-native config is applied to the native Windows home directory. MSYS2-oriented terminal tool config, including zsh, Neovim, nvim-lite, and tmux, is applied to the MSYS2 home directory.

PowerShell updates track the upstream GitHub stable release metadata because winget can lag behind PowerShell releases.
