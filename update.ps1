#!/usr/bin/env pwsh

param()

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
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

function Invoke-GitRoot {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    & git -c "safe.directory=$RootDir" -C $RootDir @Args
}

function Update-GitRoot {
    Invoke-GitRoot fetch origin main
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    Invoke-GitRoot merge --ff-only FETCH_HEAD
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Invoke-Check {
    if (-not (Test-Path -Path $BootstrapScript -PathType Leaf)) {
        Write-DotfilesLog "bootstrap script is missing: $BootstrapScript"
        exit 1
    }

    & $BootstrapScript -CheckOnly
}

Write-DotfilesLog "starting Windows update"

if (-not (Test-Command "git")) {
    Write-DotfilesLog "git is required for update"
    exit 1
}

Write-DotfilesLog "updating repository"
Update-GitRoot

Write-DotfilesLog "checking setup"
Invoke-Check
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
