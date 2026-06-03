param()

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceDir = if ($env:DOTFILES_SOURCE_DIR) { $env:DOTFILES_SOURCE_DIR } else { Join-Path $RootDir "home" }
$RepoLocalDir = Join-Path (Join-Path $RootDir ".local") "bin"
$RepoChezmoi = Join-Path $RepoLocalDir "chezmoi"
$RepoChezmoiExe = Join-Path $RepoLocalDir "chezmoi.exe"
$BootstrapScript = Join-Path $RootDir "bootstrap.ps1"

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Test-Command {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    if (Test-Path -Path $Name -PathType Leaf) {
        return $true
    }

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Resolve-Chezmoi {
    if ($env:CHEZMOI) {
        return $env:CHEZMOI
    }

    if (Test-Path -Path $RepoChezmoi -PathType Leaf) {
        return $RepoChezmoi
    }

    if (Test-Path -Path $RepoChezmoiExe -PathType Leaf) {
        return $RepoChezmoiExe
    }

    return "chezmoi"
}

function Invoke-Bootstrap {
    if (-not (Test-Path -Path $BootstrapScript -PathType Leaf)) {
        Write-DotfilesLog "bootstrap script is missing: $BootstrapScript"
        exit 1
    }

    & $BootstrapScript
}

Write-DotfilesLog "starting Windows update"

if (-not (Test-Command "git")) {
    Write-DotfilesLog "git is required for update"
    exit 1
}

Write-DotfilesLog "updating repository"
git -C $RootDir pull --ff-only

if (-not (Test-Path -Path $SourceDir -PathType Container)) {
    Write-DotfilesLog "chezmoi source directory is not ready: $SourceDir"
    Write-DotfilesLog "nothing to apply yet"
    exit 0
}

$Chezmoi = Resolve-Chezmoi

if (-not (Test-Command $Chezmoi)) {
    Write-DotfilesLog "chezmoi is unavailable; running bootstrap first"
    Invoke-Bootstrap
    $Chezmoi = Resolve-Chezmoi
}

if (-not (Test-Command $Chezmoi)) {
    Write-DotfilesLog "chezmoi is still unavailable after bootstrap"
    exit 1
}

Write-DotfilesLog "applying configuration"
& $Chezmoi --source $SourceDir apply

Write-DotfilesLog "checking repaired setup"
Invoke-Bootstrap
