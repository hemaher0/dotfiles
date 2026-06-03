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

Clone the repository:

```sh
git clone https://github.com/hemaher0/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

Install `chezmoi` if it is not already available:

```sh
mkdir -p "$HOME/.local/bin"
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
```

Preview changes:

```sh
chezmoi --source "$PWD/home" diff
```

Apply and repair the setup:

```sh
./bootstrap.sh
```

Run a health check:

```sh
bin/dot doctor
```

Install or sync missing supported components:

```sh
bin/dot doctor --fix
```

## Windows

Clone the repository:

```powershell
git clone https://github.com/hemaher0/dotfiles.git $env:USERPROFILE\.dotfiles
Set-Location $env:USERPROFILE\.dotfiles
```

Preview changes:

```powershell
chezmoi --source "$PWD/home" diff
```

Apply and repair the setup:

```powershell
.\bootstrap.ps1
```

Check only:

```powershell
.\bootstrap.ps1 -CheckOnly
```

Windows bootstrap covers winget packages, chezmoi-managed files, bundled fonts, user tools, Neovim plugins, and WezTerm readiness. It does not configure zsh on Windows.

## Commands

```sh
bin/dot doctor
bin/dot doctor --fix
bin/dot apply
bin/dot packages
bin/dot fonts
bin/dot tools
bin/dot zsh-plugins
bin/dot nvim
bin/dot update
```

## Notes

- `home/` is the chezmoi source directory.
- Machine-local zsh changes can go in `~/.config/zsh/local.zsh`.
- Machine-local WezTerm changes can go in `~/.config/wezterm/user/local.lua`.
- Termux uses `D2CodingLigatureNerdFontMono-Regular.ttf` as `~/.termux/font.ttf`.
- WSL installs Windows fonts when PowerShell is available, and also installs Linux fontconfig fonts when local WSL WezTerm is present.
