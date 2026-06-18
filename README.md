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
.\bin\dot.ps1 tui
```

Windows bootstrap covers winget packages, chezmoi-managed files, bundled fonts, user tools, Neovim plugins, and WezTerm readiness. It does not configure zsh or tmux on Windows.

Update the repository and check the Windows setup:

```powershell
.\update.ps1
```

Check Windows component status, including the pinned PowerShell release target, and update PowerShell only:

```powershell
.\bin\dot.ps1 update --check
.\bin\dot.ps1 update --update package-pwsh
```

Use a separate development worktree when you want to validate changes before applying them to the real checkout:

```powershell
.\bin\dot.ps1 dev-ref
.\bin\dot.ps1 dev-ref dev
.\bin\dot-dev.ps1 update --check
.\bin\dot.ps1 dev-apply
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
bin/dot tui
bin/dot dev-ref
bin/dot-dev update --check
bin/dot dev-apply
.\bin\dot.ps1 tui
.\bin\dot.ps1 dev-ref
.\bin\dot-dev.ps1 update --check
.\bin\dot.ps1 dev-apply
bin/dot update --raw
.\bin\dot.ps1 update --raw
bin/dot update --sync config-tmux
bin/dot update --install tool-zoxide
bin/dot update --install plugin-nvim
bin/dot update --update plugin-zsh
bin/dot update --build package-zsh
bin/dot update --build package-tmux
bin/dot update --install plugin-tmux
bin/dot doctor
bin/dot doctor --fix
bin/dot sync
bin/dot bootstrap
```

`bin/dot install` performs the complete setup and may use sudo for platform packages. `bin/dot install --user` uses the user-local strategy without sudo. On native Windows, use `.\bin\dot.ps1` for the same status and TUI workflow. `bin/dot update` pulls the repository and prints a component status table with category, group, scope, and stable component IDs. `bin/dot update --check` prints the same table without pulling, and `bin/dot update --raw` prints machine-readable status rows for tooling. `bin/dot tui` opens the Ratatui component dashboard, building it locally with Cargo when no compiled binary exists. Use `--sync <config-id>`, `--install <id>`, `--update <id>`, and `--build <id>` to run a single component action explicitly. `sync` is reserved for config components. Plugin leaf rows are status-only; use group IDs such as `plugin-nvim`, `plugin-zsh`, and `plugin-tmux` for plugin install/update actions. `bin/dot sync` syncs the full chezmoi source directory, `home/`, into `$HOME`.

`bin/dot` and `.\bin\dot.ps1` run the real checkout. `bin/dot-dev` and `.\bin\dot-dev.ps1` create or reuse an ignored `.dev/` worktree and run commands from that development checkout instead. The development ref defaults to `dev`; change it per machine with `bin/dot dev-ref <git-ref>` or `.\bin\dot.ps1 dev-ref <git-ref>`, or override it for one session with `DOTFILES_DEV_REF`. After validating in `.dev/`, run `bin/dot dev-apply` or `.\bin\dot.ps1 dev-apply` to copy changed and untracked files from `.dev/` into the real checkout.

## Notes

- `home/` is the chezmoi source directory.
- Machine-local zsh changes can go in `~/.config/zsh/local.zsh`.
- Machine-local tmux changes can go in `~/.config/tmux/tmux.conf.local`.
- Machine-local WezTerm changes can go in `~/.config/wezterm/user/local.lua`.
- WSL installs Windows fonts when PowerShell is available, and also installs Linux fontconfig fonts when local WSL WezTerm is present.
