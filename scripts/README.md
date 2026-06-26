# Scripts

Repository scripts for installing and updating components that are not managed directly by chezmoi. `bin/dot install` and `bin/dot update` call these scripts as internal workflow steps.

## Antidote

Install or update Antidote:

```sh
scripts/install-antidote.sh
```

Use `update` to require an existing Antidote checkout and update cloned bundles:

```sh
scripts/install-antidote.sh update
```

The script clones Antidote into `${ZDOTDIR:-$HOME}/.antidote` by default. It does not write `~/.zshrc`, change the login shell, or start zsh. Dotfiles remain managed by chezmoi.

## Fonts

Install or update bundled terminal fonts:

```sh
scripts/install-fonts.sh
```

On Windows:

```powershell
.\scripts\install-fonts.ps1
.\scripts\install-fonts.ps1 install font-red-hat-mono
```

The font scripts install bundled files from `assets/fonts` and do not download anything. Linux installs fonts into `~/.local/share/fonts/dotfiles` and refreshes `fontconfig`. WSL installs Windows fonts through PowerShell when possible, and also installs Linux fontconfig fonts when a local WSL `wezterm` binary is present.

## User Tools

Install or update prebuilt user-local CLI tools:

```sh
scripts/install-user-tools.sh
scripts/install-user-tools.sh install zoxide
scripts/install-user-tools.sh update direnv
```

This installs `zoxide` and `direnv` from official release binaries into `~/.local/bin`. Windows uses winget package IDs for the same tools:

```powershell
.\scripts\install-user-tools.ps1 install tool-zoxide
```

## tmux

Install or update the Oh my tmux checkout used by the managed tmux config:

```sh
scripts/install-tmux-config.sh
scripts/install-tmux-config.sh update
```

## Neovim

Install or update plugins for the default Neovim profile:

```sh
scripts/install-neovim-plugins.sh
scripts/install-neovim-plugins.sh install plugin-nvim-smart-splits
```

Use `NVIM_APPNAME` to target another Neovim profile.
