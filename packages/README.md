# Package Scripts

These scripts install baseline tools for each supported platform. They can be run directly, and the bootstrap or doctor flows may call them when required commands are missing.

## Scripts

| Script | Platform |
| --- | --- |
| `ubuntu.sh` | Ubuntu and Ubuntu-like Linux environments with `apt-get`. |
| `wsl.sh` | Ubuntu on WSL. Delegates to `ubuntu.sh` after verifying WSL. |
| `termux.sh` | Termux on Android. |
| `windows.ps1` | Windows with `winget`. |

## Usage

Run the detected POSIX script:

```sh
bin/dot packages
```

Run a specific POSIX script:

```sh
packages/ubuntu.sh
packages/wsl.sh
packages/termux.sh
```

Run the Windows script:

```powershell
.\packages\windows.ps1
```

Review each script before running it on a new machine. Package names and availability can vary by OS version.
