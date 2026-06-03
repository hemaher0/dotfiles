# Dotfiles

Personal dotfiles for rebuilding my shell, editor, and terminal setup across Linux, WSL, Ubuntu, Termux, and Windows.

The repository is managed with `chezmoi`. Bootstrap scripts handle the repeatable parts around package setup, fonts, Neovim plugins, zsh plugins, and WezTerm configuration.

## What's Included

- zsh configuration with Antidote-managed plugins
- Powerlevel10k prompt configuration
- Neovim configuration with Lazy.nvim
- WezTerm configuration
- Red Hat Mono and D2CodingLigature Nerd Font files
- zoxide and direnv installers
- Platform package scripts for Ubuntu, WSL, Termux, and Windows

## Quick Start

### Ubuntu

```sh
git clone https://github.com/hemaher0/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./bootstrap.sh
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
./bootstrap.sh
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

Windows bootstrap covers winget packages, chezmoi-managed files, bundled fonts, user tools, Neovim plugins, and WezTerm readiness. It does not configure zsh on Windows.

Update the repository and reapply the Windows setup:

```powershell
.\update.ps1
```

### Build From Source

Use the user-local build path when `apt` cannot be used or Ubuntu packages are not suitable:

```sh
git clone https://github.com/hemaher0/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
bin/dot packages build
bin/dot apply
bin/dot doctor
```

This installs into `~/.local`, uses prebuilt zoxide, direnv, and Neovim releases, and builds missing zsh from source. zsh requires existing build tools such as `make`, `xz`, and a C compiler. It does not change the login shell.

## Commands

```sh
bin/dot doctor
bin/dot doctor --fix
bin/dot apply
bin/dot packages
bin/dot packages update
bin/dot packages upgrade
bin/dot packages build
bin/dot fonts
bin/dot tools
bin/dot zsh-plugins
bin/dot nvim
bin/dot update
```

`bin/dot apply` applies the chezmoi source directory, `home/`, into `$HOME`. It writes managed dotfiles only; package installs, fonts, and plugins are handled by the other commands.

## Notes

- `home/` is the chezmoi source directory.
- Machine-local zsh changes can go in `~/.config/zsh/local.zsh`.
- Machine-local WezTerm changes can go in `~/.config/wezterm/user/local.lua`.
- Termux uses `D2CodingLigatureNerdFontMono-Regular.ttf` as `~/.termux/font.ttf`.
- WSL installs Windows fonts when PowerShell is available, and also installs Linux fontconfig fonts when local WSL WezTerm is present.
