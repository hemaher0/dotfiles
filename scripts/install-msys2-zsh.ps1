param(
    [ValidateSet("install", "update", "help")]
    [string]$Command = "install"
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Msys2Root = if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { "C:\msys64" }
$Msys2UsrBin = Join-Path $Msys2Root "usr\bin"
$Bash = Join-Path $Msys2UsrBin "bash.exe"
$Cygpath = Join-Path $Msys2UsrBin "cygpath.exe"
$Pacman = Join-Path $Msys2UsrBin "pacman.exe"
$Zsh = Join-Path $Msys2UsrBin "zsh.exe"

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Show-Usage {
    @"
Usage: install-msys2-zsh.ps1 [install|update|help]

Installs and updates the MSYS2 zsh runtime used on native Windows:
  - zsh
  - git
  - Antidote and zsh bundles in the Windows user profile
"@
}

function Assert-Msys2 {
    foreach ($Path in @($Bash, $Cygpath, $Pacman)) {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            Write-DotfilesLog "MSYS2 is required: $Path"
            Write-DotfilesLog "run: .\bin\dot.ps1 update --install package-msys2"
            exit 1
        }
    }
}

function ConvertTo-MsysPath {
    param([string]$Path)

    $Output = & $Cygpath -u $Path
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Output)) {
        Write-DotfilesLog "failed to convert path for MSYS2: $Path"
        exit 1
    }

    return ($Output | Select-Object -First 1).Trim()
}

function Invoke-Msys2Bash {
    param([string]$Script)

    Assert-Msys2

    $OldPath = $env:Path
    $OldHome = $env:HOME
    $OldMsystem = $env:MSYSTEM
    $OldChereInvoking = $env:CHERE_INVOKING

    try {
        $env:Path = "$Msys2UsrBin;$env:Path"
        $env:HOME = ConvertTo-MsysPath $HOME
        $env:MSYSTEM = "MSYS"
        $env:CHERE_INVOKING = "1"

        & $Bash -lc $Script
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
    finally {
        $env:Path = $OldPath
        $env:HOME = $OldHome
        $env:MSYSTEM = $OldMsystem
        $env:CHERE_INVOKING = $OldChereInvoking
    }
}

function Install-ZshRuntime {
    Assert-Msys2

    Write-DotfilesLog "installing MSYS2 zsh runtime"
    Invoke-Msys2Bash "pacman -Sy --needed --noconfirm zsh git"

    if (-not (Test-Path -Path $Zsh -PathType Leaf)) {
        Write-DotfilesLog "MSYS2 zsh was not installed: $Zsh"
        exit 1
    }
}

function Update-ZshRuntime {
    Assert-Msys2

    Write-DotfilesLog "updating MSYS2 zsh runtime"
    Invoke-Msys2Bash "pacman -Syu --needed --noconfirm zsh git"
}

function Install-ZshPlugins {
    if (-not (Test-Path -Path $Zsh -PathType Leaf)) {
        Write-DotfilesLog "MSYS2 zsh is required for zsh plugin install"
        exit 1
    }

    $RepoPath = ConvertTo-MsysPath $RootDir
    Write-DotfilesLog "installing zsh plugins with MSYS2"
    Invoke-Msys2Bash "cd '$RepoPath' && sh ./scripts/install-antidote.sh install && sh ./scripts/install-antidote.sh update"
}

if ($Command -eq "help") {
    Show-Usage
    exit 0
}

switch ($Command) {
    "install" {
        Install-ZshRuntime
        Install-ZshPlugins
    }
    "update" {
        Update-ZshRuntime
        Install-ZshPlugins
    }
}
