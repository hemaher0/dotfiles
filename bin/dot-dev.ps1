param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DotArgs
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$DevDir = Join-Path $RootDir ".dev"
$DevConfigPath = Join-Path (Join-Path $RootDir ".local") "dev.json"
$DefaultDevRef = "dev"

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-DevRef {
    if (-not [string]::IsNullOrWhiteSpace($env:DOTFILES_DEV_REF)) {
        return $env:DOTFILES_DEV_REF
    }

    if (Test-Path -Path $DevConfigPath -PathType Leaf) {
        try {
            $Config = Get-Content -Raw -Path $DevConfigPath | ConvertFrom-Json
            if ($Config.ref -and -not [string]::IsNullOrWhiteSpace([string]$Config.ref)) {
                return [string]$Config.ref
            }
        }
        catch {
            Write-DotfilesLog "warning: ignoring invalid development ref config: $DevConfigPath"
        }
    }

    return $DefaultDevRef
}

function Assert-Git {
    if (-not (Test-Command "git")) {
        Write-DotfilesLog "git is required for development worktree setup"
        exit 1
    }

    $IsRepo = & git -C $RootDir rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $IsRepo -ne "true") {
        Write-DotfilesLog "not a git repository: $RootDir"
        exit 1
    }
}

function Test-GitWorktree {
    param([string]$Path)

    if (-not (Test-Path -Path $Path -PathType Container)) {
        return $false
    }

    $IsRepo = & git -C $Path rev-parse --is-inside-work-tree 2>$null
    return $LASTEXITCODE -eq 0 -and $IsRepo -eq "true"
}

function Test-RefExists {
    param([string]$Ref)

    & git -C $RootDir rev-parse --verify --quiet $Ref 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Test-DevRootDirty {
    $Dirty = & git -C $DevDir status --porcelain
    return -not [string]::IsNullOrWhiteSpace(($Dirty -join "`n"))
}

function Initialize-DevWorktree {
    param([string]$Ref)

    Assert-Git

    if (Test-Path -Path $DevDir -PathType Container) {
        if (-not (Test-GitWorktree $DevDir)) {
            Write-DotfilesLog "development path exists but is not a git worktree: $DevDir"
            exit 1
        }

        if (Test-DevRootDirty) {
            Write-DotfilesLog "using existing dirty development root: $DevDir"
            return
        }

        Write-DotfilesLog "checking out development ref: $Ref"
        git -C $DevDir checkout $Ref
        return
    }

    if (Test-RefExists $Ref) {
        Write-DotfilesLog "creating development worktree at $DevDir"
        git -C $RootDir worktree add $DevDir $Ref
    }
    else {
        Write-DotfilesLog "creating development branch and worktree: $Ref"
        git -C $RootDir worktree add -b $Ref $DevDir HEAD
    }
}

$DevRef = Get-DevRef
Initialize-DevWorktree $DevRef

$DevDot = Join-Path (Join-Path $DevDir "bin") "dot.ps1"
if (-not (Test-Path -Path $DevDot -PathType Leaf)) {
    Write-DotfilesLog "development dot.ps1 is missing: $DevDot"
    exit 1
}

& $DevDot @DotArgs
if (-not $?) {
    exit 1
}

if ($null -ne $LASTEXITCODE) {
    exit $LASTEXITCODE
}
