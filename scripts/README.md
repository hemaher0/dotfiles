# Scripts

Repository scripts for installing and updating tools that are not managed directly by chezmoi.

## Antidote

Install or update Antidote:

```sh
scripts/install-antidote.sh
```

Run through the command wrapper:

```sh
bin/dot zsh-plugins
```

Use `update` to require an existing Antidote checkout and update cloned bundles:

```sh
bin/dot zsh-plugins update
```

The script clones Antidote into `${ZDOTDIR:-$HOME}/.antidote` by default. It does not write `~/.zshrc`, change the login shell, or start zsh. Dotfiles remain managed by chezmoi.

## Fonts

Install or update bundled terminal fonts:

```sh
scripts/install-fonts.sh
```

Run through the command wrapper:

```sh
bin/dot fonts
```

On Windows:

```powershell
.\scripts\install-fonts.ps1
```

The font scripts install bundled files from `assets/fonts` and do not download anything. Linux installs fonts into `~/.local/share/fonts/dotfiles` and refreshes `fontconfig`. WSL installs Windows fonts through PowerShell when possible, and also installs Linux fontconfig fonts when a local WSL `wezterm` binary is present. Termux installs `D2CodingLigatureNerdFontMono-Regular.ttf` as `~/.termux/font.ttf` because Termux uses a single terminal font file by default.

## User Tools

Install or update prebuilt user-local CLI tools:

```sh
scripts/install-user-tools.sh
```

Run through the command wrapper:

```sh
bin/dot tools
```

This installs `zoxide` and `direnv` without building from source. POSIX-like systems install official release binaries into `~/.local/bin`. Windows uses winget package IDs for the same tools.

## Neovim

Install or update plugins for the default Neovim profile:

```sh
scripts/install-neovim-plugins.sh
```

Run through the command wrapper:

```sh
bin/dot nvim
```

Use `NVIM_APPNAME` to target another Neovim profile.
