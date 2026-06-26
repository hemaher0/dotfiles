# Package Scripts

These scripts are implementation details for the package setup used by `bin/dot install`. They install or update baseline tools for each supported platform.

## Scripts

| Script | Platform |
| --- | --- |
| `ubuntu.sh` | Ubuntu and Ubuntu-like Linux environments with `apt-get`. |
| `wsl.sh` | Ubuntu on WSL. Delegates to `ubuntu.sh` after verifying WSL. |
| `windows.ps1` | Windows with `winget`. |

## Usage

Run a specific POSIX script while maintaining the package flows:

```sh
packages/ubuntu.sh install
packages/ubuntu.sh update
packages/ubuntu.sh upgrade
packages/ubuntu.sh user
packages/ubuntu.sh user-libevent
packages/ubuntu.sh user-ncurses
packages/ubuntu.sh user-zsh
packages/ubuntu.sh user-tmux
packages/wsl.sh install
```

Run the Windows script:

```powershell
.\packages\windows.ps1
.\packages\windows.ps1 update
.\packages\windows.ps1 upgrade
.\packages\windows.ps1 install package-pwsh
.\packages\windows.ps1 install package-msys2
```

`update` refreshes package indexes or sources. `upgrade` is limited to the baseline packages managed by this repository; it does not run full-system upgrade commands such as `apt upgrade`, `pkg upgrade`, or `winget upgrade --all`.

PowerShell updates track the GitHub stable release metadata and install the matching GitHub release MSI because winget can lag behind upstream releases. Windows zsh support expects MSYS2 at the standard `C:\msys64` location or on PATH; dotfile sync applies Windows-native config to the native Windows home directory and applies zsh, Neovim, nvim-lite, and tmux config to the MSYS2 home directory.

On Ubuntu, `install` uses `apt` packages for Rust, ncurses, libevent, and tmux. `user` installs supported components into `~/.local`, uses prebuilt zoxide, direnv, Neovim releases, rustup toolchains, ncurses/libevent/tmux/zsh stable release tarballs, and the Oh my tmux checkout. It is used by `bin/dot install --user`. Targeted `user-*` commands are internal entry points for component actions. Source builds still require compiler prerequisites such as `make`, `pkg-config`, `xz`, a C compiler, and `yacc` or `bison` for tmux. zsh does not clone or build from the SourceForge Git development repository, and the install flow does not change the login shell. Set `DOTFILES_FORCE_USER_INSTALL=1` to reinstall even when commands already exist.

Review each script before running it on a new machine. Package names and availability can vary by OS version.
