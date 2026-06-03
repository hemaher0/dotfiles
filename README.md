# Dotfiles

Personal dotfiles for rebuilding my shell, editor, terminal, and tmux setup across Linux, WSL, Ubuntu, and Windows.

The repository is managed with `chezmoi`. Bootstrap scripts handle the repeatable parts around package setup, fonts, Neovim plugins, zsh plugins, tmux configuration, and WezTerm configuration.

## What's Included

- zsh configuration with Antidote-managed plugins
- Powerlevel10k prompt configuration
- Neovim configuration with Lazy.nvim
- tmux configuration with Oh my tmux
- WezTerm configuration
- Red Hat Mono and D2CodingLigature Nerd Font files
- zoxide and direnv installers
- Platform package scripts for Ubuntu, WSL, and Windows

## Quick Start

### Ubuntu

```sh
git clone https://github.com/hemaher0/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
bin/dot install
bin/dot doctor
```

Preview first when `chezmoi` is already installed:

```sh
chezmoi --source "$PWD/home" diff
```

### Ubuntu (WSL)

```sh
git clone https://github.com/hemaher0/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
bin/dot install
bin/dot doctor
```

WSL uses the Ubuntu package flow and installs Windows fonts through PowerShell when available.

### Windows

```powershell
git clone https://github.com/hemaher0/dotfiles.git $env:USERPROFILE\.dotfiles
Set-Location $env:USERPROFILE\.dotfiles
.\bootstrap.ps1
.\bootstrap.ps1 -CheckOnly
```

Windows bootstrap covers winget packages, chezmoi-managed files, bundled fonts, user tools, Neovim plugins, and WezTerm readiness. It does not configure zsh or tmux on Windows.

Update the repository and reapply the Windows setup:

```powershell
.\update.ps1
```

### User-Local Install

Use the user-local install path when `apt` cannot be used or Ubuntu packages are not suitable:

```sh
git clone https://github.com/hemaher0/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
bin/dot install --user
bin/dot doctor
```

This installs supported components into `~/.local`, uses prebuilt zoxide, direnv, Neovim releases, rustup toolchains, ncurses/libevent/tmux/zsh stable release tarballs, and the Oh my tmux checkout. Source builds still require compiler prerequisites such as `make`, `pkg-config`, `xz`, a C compiler, and `yacc` or `bison` for tmux. It does not change the login shell.

## Commands

```sh
bin/dot install
bin/dot install --user
bin/dot update
bin/dot update --install tool-zoxide
bin/dot update --update nvim-lazy
bin/dot update --build package-zsh
bin/dot update --build package-tmux
bin/dot update --install tmux-oh-my
bin/dot doctor
bin/dot doctor --fix
bin/dot apply
bin/dot bootstrap
```

`bin/dot install` performs the complete setup and may use sudo for platform packages. `bin/dot install --user` uses the user-local strategy without sudo. `bin/dot update` pulls the repository and prints a component status table with stable component IDs. Use `bin/dot update --install <id>`, `--update <id>`, or `--build <id>` to run a single component action explicitly. `bin/dot apply` only applies the chezmoi source directory, `home/`, into `$HOME`.

## Notes

- `home/` is the chezmoi source directory.
- Machine-local zsh changes can go in `~/.config/zsh/local.zsh`.
- Machine-local tmux changes can go in `~/.config/tmux/tmux.conf.local`.
- Machine-local WezTerm changes can go in `~/.config/wezterm/user/local.lua`.
- WSL installs Windows fonts when PowerShell is available, and also installs Linux fontconfig fonts when local WSL WezTerm is present.
