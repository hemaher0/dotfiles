param(
    [Parameter(Position = 0)]
    [string]$CommandName = "help",
    [switch]$Raw,
    [switch]$Check,
    [switch]$CheckUpdates,
    [string]$Install,
    [string]$Update,
    [string]$Sync,
    [string]$Build,
    [switch]$Fix,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$SourceDir = if ($env:DOTFILES_SOURCE_DIR) { $env:DOTFILES_SOURCE_DIR } else { Join-Path $RootDir "home" }
$RepoLocalDir = Join-Path (Join-Path $RootDir ".local") "bin"
$RepoChezmoi = Join-Path $RepoLocalDir "chezmoi.exe"
$BootstrapScript = Join-Path $RootDir "bootstrap.ps1"
$DevDir = Join-Path $RootDir ".dev"
$DevConfigPath = Join-Path (Join-Path $RootDir ".local") "dev.json"
$DefaultDevRef = "dev"
$CommandArgs = @()
if ($RemainingArgs) {
    $CommandArgs += $RemainingArgs
}
$Msys2Root = if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { "C:\msys64" }
$Msys2UsrBin = Join-Path $Msys2Root "usr\bin"
$Msys2Pacman = Join-Path $Msys2UsrBin "pacman.exe"
$Msys2Zsh = Join-Path $Msys2UsrBin "zsh.exe"
$PowerShellStableBuildInfoUrl = "https://aka.ms/pwsh-buildinfo-stable"
$WingetManagedPackages = @(
    @{ ComponentId = "package-git"; Id = "Git.Git" },
    @{ ComponentId = "package-msys2"; Id = "MSYS2.MSYS2" },
    @{ ComponentId = "package-chezmoi"; Id = "twpayne.chezmoi" },
    @{ ComponentId = "package-wezterm"; Id = "wez.wezterm" },
    @{ ComponentId = "dependency-rust"; Id = "Rustlang.Rustup" }
)

if ($Raw) { $CommandArgs += "--raw" }
if ($Check) { $CommandArgs += "--check" }
if ($CheckUpdates) { $CommandArgs += "--check-updates" }
if ($Install) { $CommandArgs += @("--install", $Install) }
if ($Update) { $CommandArgs += @("--update", $Update) }
if ($Sync) { $CommandArgs += @("--sync", $Sync) }
if ($Build) { $CommandArgs += @("--build", $Build) }
if ($Fix) { $CommandArgs += "--fix" }
if ($Help) { $CommandArgs += "--help" }

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Show-Usage {
    @"
Usage: dot.ps1 <command>

Commands:
  install      Install the Windows dotfiles setup
  update       Pull the repository, then show component status
  tui          Open the Ratatui component dashboard
  doctor       Check local requirements
  sync         Sync the chezmoi source directory
  dev-ref      Show or set the development Git ref
  dev-apply    Apply validated .dev changes to this checkout
  bootstrap    Run the Windows bootstrap script
  help         Show this help
"@
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

function Resolve-Msys2Command {
    param([string]$Name)

    $Candidate = Join-Path $Msys2UsrBin "$Name.exe"
    if (Test-Path -Path $Candidate -PathType Leaf) {
        return $Candidate
    }

    foreach ($Prefix in @("ucrt64", "mingw64", "clang64", "clangarm64")) {
        $Candidate = Join-Path (Join-Path $Msys2Root "$Prefix\bin") "$Name.exe"
        if (Test-Path -Path $Candidate -PathType Leaf) {
            return $Candidate
        }
    }

    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($Command -and $Command.Source -like "$Msys2Root*") {
        return $Command.Source
    }

    return ""
}

function Test-Msys2Command {
    param([string]$Name)

    -not [string]::IsNullOrWhiteSpace((Resolve-Msys2Command $Name))
}

function Get-Msys2HomePath {
    $Bash = Resolve-Msys2Command "bash"
    if (-not [string]::IsNullOrWhiteSpace($Bash)) {
        try {
            $HomePath = & $Bash -lc 'cygpath -w "$HOME"' 2>$null | Select-Object -First 1
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($HomePath)) {
                return $HomePath.Trim()
            }
        }
        catch {
        }
    }

    return Join-Path "C:\msys64\home" $env:USERNAME
}

function Get-WindowsChezmoiTargets {
    return @(
        ".config/wezterm"
    )
}

function Get-Msys2ChezmoiTargets {
    return @(
        ".zshenv",
        ".zshrc",
        ".p10k.zsh",
        ".config/zsh",
        ".config/nvim",
        ".config/nvim-lite",
        ".config/tmux"
    )
}

function Get-WindowsChezmoiTargetsForComponent {
    param([string]$ComponentId = "")

    switch ($ComponentId) {
        "" { return Get-WindowsChezmoiTargets }
        "config-wezterm" { return @(".config/wezterm") }
        "config-wezterm-smart-splits" { return @(".config/wezterm/user/smart_splits.lua") }
        default { return @() }
    }
}

function Get-Msys2ChezmoiTargetsForComponent {
    param([string]$ComponentId = "")

    switch ($ComponentId) {
        "" { return Get-Msys2ChezmoiTargets }
        "config-zshenv" { return @(".zshenv") }
        "config-zshrc" { return @(".zshrc") }
        "config-p10k" { return @(".p10k.zsh") }
        "config-zsh-plugins" { return @(".config/zsh/plugins.txt") }
        "config-nvim" { return @(".config/nvim") }
        "config-nvim-lite" { return @(".config/nvim-lite") }
        "config-tmux" { return @(".config/tmux") }
        default { return @() }
    }
}

function Convert-ChezmoiTargetToPath {
    param(
        [string]$Root,
        [string]$Target
    )

    return Join-Path $Root ($Target -replace "/", "\")
}

function Ensure-ChezmoiTargetParents {
    param([string[]]$Paths)

    foreach ($Path in $Paths) {
        $Parent = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($Parent)) {
            New-Item -ItemType Directory -Path $Parent -Force | Out-Null
        }
    }
}

function New-BackupPath {
    param(
        [string]$Path,
        [string]$Timestamp
    )

    $Base = "$Path.dotfiles-backup-$Timestamp"
    $Candidate = $Base
    $Index = 1
    while (Test-Path -LiteralPath $Candidate) {
        $Candidate = "$Base-$Index"
        $Index += 1
    }

    return $Candidate
}

function Backup-StaleWindowsConfigPaths {
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    foreach ($Target in (Get-Msys2ChezmoiTargets)) {
        $Path = Convert-ChezmoiTargetToPath -Root $HOME -Target $Target
        if (-not (Test-Path -LiteralPath $Path)) {
            continue
        }

        $BackupPath = New-BackupPath -Path $Path -Timestamp $Timestamp
        Write-DotfilesLog "backing up stale Windows config: $Path -> $BackupPath"
        Move-Item -LiteralPath $Path -Destination $BackupPath
    }
}

function Invoke-Msys2RepoScript {
    param(
        [string]$ScriptPath,
        [string[]]$ScriptArgs
    )

    $Bash = Resolve-Msys2Command "bash"
    if ([string]::IsNullOrWhiteSpace($Bash)) {
        Write-DotfilesLog "MSYS2 bash is required"
        exit 1
    }

    $PreviousRoot = $env:DOTFILES_ROOT
    $PreviousScript = $env:DOTFILES_SCRIPT
    $env:DOTFILES_ROOT = $RootDir
    $env:DOTFILES_SCRIPT = $ScriptPath
    try {
        & $Bash -lc 'export PATH="/ucrt64/bin:/mingw64/bin:/clang64/bin:/clangarm64/bin:$PATH"; export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"; export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"; export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"; export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"; cd "$(cygpath -u "$DOTFILES_ROOT")" && "$DOTFILES_SCRIPT" "$@"' dotfiles @ScriptArgs
    }
    finally {
        $env:DOTFILES_ROOT = $PreviousRoot
        $env:DOTFILES_SCRIPT = $PreviousScript
    }

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Resolve-Chezmoi {
    if ($env:CHEZMOI) {
        return $env:CHEZMOI
    }

    if (Test-Path -Path $RepoChezmoi -PathType Leaf) {
        return $RepoChezmoi
    }

    return "chezmoi"
}

function Get-LocalAppData {
    if ($env:LOCALAPPDATA) {
        return $env:LOCALAPPDATA
    }

    return Join-Path $HOME "AppData\Local"
}

function Update-ProcessPath {
    $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $KnownUserPaths = @(
        (Join-Path (Get-LocalAppData) "Microsoft\WindowsApps"),
        (Join-Path (Get-LocalAppData) "Microsoft\WinGet\Links")
    )
    $Seen = @{}
    $PathParts = @()

    foreach ($PathEntry in (@($MachinePath, $UserPath, $env:Path) + $KnownUserPaths)) {
        foreach ($Part in ([string]$PathEntry -split ";")) {
            if ([string]::IsNullOrWhiteSpace($Part)) {
                continue
            }

            $Key = $Part.Trim().ToLowerInvariant()
            if (-not $Seen.ContainsKey($Key)) {
                $Seen[$Key] = $true
                $PathParts += $Part.Trim()
            }
        }
    }

    $env:Path = $PathParts -join ";"
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

function Set-DevRef {
    param([string]$Ref)

    if ([string]::IsNullOrWhiteSpace($Ref)) {
        Write-DotfilesLog "dev-ref requires a Git ref"
        exit 1
    }

    $Parent = Split-Path -Parent $DevConfigPath
    New-Item -ItemType Directory -Path $Parent -Force | Out-Null

    [PSCustomObject]@{ ref = $Ref } |
        ConvertTo-Json |
        Set-Content -Path $DevConfigPath -Encoding UTF8

    Write-DotfilesLog "development ref set to $Ref"
}

function Invoke-GitRoot {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    & git -c "safe.directory=$RootDir" -C $RootDir @Args
}

function Invoke-GitDev {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    & git -c "safe.directory=$DevDir" -C $DevDir @Args
}

function Invoke-DevRefCommand {
    param([string[]]$Args)

    if ($Args.Count -eq 0) {
        Get-DevRef
        return
    }

    if ($Args.Count -eq 1) {
        Set-DevRef $Args[0]
        return
    }

    Write-DotfilesLog "usage: dot.ps1 dev-ref [git-ref]"
    exit 1
}

function Assert-GitRootClean {
    $Dirty = Invoke-GitRoot status --porcelain
    if ($LASTEXITCODE -ne 0) {
        Write-DotfilesLog "failed to inspect root checkout"
        exit 1
    }

    if ($Dirty) {
        Write-DotfilesLog "root checkout has changes; commit, stash, or remove them before dev-apply"
        exit 1
    }
}

function Assert-DevRoot {
    if (-not (Test-Path -Path $DevDir -PathType Container)) {
        Write-DotfilesLog "development root is missing: $DevDir"
        Write-DotfilesLog "run: .\bin\dot-dev.ps1 update --check"
        exit 1
    }

    $IsRepo = Invoke-GitDev rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $IsRepo -ne "true") {
        Write-DotfilesLog "development root is not a git worktree: $DevDir"
        exit 1
    }
}

function Resolve-RepoPath {
    param(
        [string]$Base,
        [string]$RelativePath
    )

    $FullPath = [System.IO.Path]::GetFullPath((Join-Path $Base $RelativePath))
    $BasePath = [System.IO.Path]::GetFullPath($Base).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if (-not ($FullPath -eq $BasePath -or $FullPath.StartsWith($BasePath + [System.IO.Path]::DirectorySeparatorChar) -or $FullPath.StartsWith($BasePath + [System.IO.Path]::AltDirectorySeparatorChar))) {
        Write-DotfilesLog "refusing path outside repository: $RelativePath"
        exit 1
    }

    return $FullPath
}

function Copy-DevPathToRoot {
    param([string]$RelativePath)

    $Source = Resolve-RepoPath $DevDir $RelativePath
    $Target = Resolve-RepoPath $RootDir $RelativePath
    $Parent = Split-Path -Parent $Target
    if ($Parent) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    Copy-Item -LiteralPath $Source -Destination $Target -Force
}

function Remove-RootPath {
    param([string]$RelativePath)

    $Target = Resolve-RepoPath $RootDir $RelativePath
    if (Test-Path -LiteralPath $Target -PathType Leaf) {
        Remove-Item -LiteralPath $Target -Force
    }
}

function Invoke-DevApply {
    if ($CommandArgs.Count -gt 0) {
        Write-DotfilesLog "usage: dot.ps1 dev-apply"
        exit 1
    }

    Assert-DevRoot
    Assert-GitRootClean

    $RootHead = Invoke-GitRoot rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($RootHead)) {
        Write-DotfilesLog "failed to resolve root HEAD"
        exit 1
    }

    $Deleted = @(Invoke-GitDev diff --name-only --diff-filter=D $RootHead --)
    $Changed = @(Invoke-GitDev diff --name-only --diff-filter=ACMRT $RootHead --)
    $Untracked = @(Invoke-GitDev ls-files --others --exclude-standard)

    foreach ($Path in $Deleted) {
        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            Write-DotfilesLog "remove: $Path"
            Remove-RootPath $Path
        }
    }

    foreach ($Path in ($Changed + $Untracked)) {
        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            Write-DotfilesLog "apply: $Path"
            Copy-DevPathToRoot $Path
        }
    }

    Write-DotfilesLog "development changes applied to root checkout"
}

function Get-CommandVersion {
    param([string]$Name)

    try {
        $Output = & $Name --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $Output) {
            return (($Output | Select-Object -First 1) -replace "^[^0-9]*", "" -replace "[\s,].*$", "")
        }
    }
    catch {
    }

    return "present"
}

function Get-PowerShellVersion {
    if (-not (Test-Command "pwsh")) {
        return ""
    }

    try {
        $Output = & pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
        if ($LASTEXITCODE -eq 0 -and $Output) {
            return ($Output | Select-Object -First 1).Trim()
        }
    }
    catch {
    }

    return Get-CommandVersion "pwsh"
}

function Get-Msys2CommandVersion {
    param([string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return ""
    }

    try {
        $Output = & $Path --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $Output) {
            return (($Output | Select-Object -First 1) -replace "^[^0-9]*", "" -replace "[\s,].*$", "")
        }
    }
    catch {
    }

    return "present"
}

function Get-PowerShellStableReleaseInfo {
    try {
        $Release = Invoke-RestMethod -Uri $PowerShellStableBuildInfoUrl -Headers @{ "User-Agent" = "dotfiles" } -ErrorAction Stop
        $Tag = [string]$Release.ReleaseTag
        if ([string]::IsNullOrWhiteSpace($Tag)) {
            return [PSCustomObject]@{ Status = "unknown"; Tag = ""; Version = $null; ReleaseDate = ""; Relation = "release metadata missing tag" }
        }

        $VersionText = $Tag -replace "^v", ""
        $Version = ConvertTo-VersionOrNull $VersionText
        if ($null -eq $Version) {
            return [PSCustomObject]@{ Status = "unknown"; Tag = $Tag; Version = $null; ReleaseDate = ""; Relation = "release metadata has invalid tag" }
        }

        return [PSCustomObject]@{
            Status = "ok"
            Tag = $Tag
            Version = $Version
            ReleaseDate = [string]$Release.ReleaseDate
            Relation = "github stable"
        }
    }
    catch {
        return [PSCustomObject]@{ Status = "unknown"; Tag = ""; Version = $null; ReleaseDate = ""; Relation = "github stable check failed" }
    }
}

function ConvertTo-VersionOrNull {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $VersionText = ($Value -replace "^[^0-9]*", "" -replace "[^0-9.].*$", "")
    try {
        return [Version]$VersionText
    }
    catch {
        return $null
    }
}

function Get-RepoVersion {
    if (-not (Test-Command "git")) {
        return ""
    }

    $IsRepo = Invoke-GitRoot rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $IsRepo -ne "true") {
        return ""
    }

    $Branch = Invoke-GitRoot rev-parse --abbrev-ref HEAD 2>$null
    $Sha = Invoke-GitRoot rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $Branch -and $Sha) {
        return "$Branch@$Sha"
    }

    return ""
}

function Get-GitUpdateInfo {
    if (-not (Test-Command "git")) {
        return [PSCustomObject]@{ Status = "unknown"; Policy = "git upstream"; Relation = "git unavailable" }
    }

    $IsRepo = & git -C $RootDir rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $IsRepo -ne "true") {
        return [PSCustomObject]@{ Status = "unknown"; Policy = "git upstream"; Relation = "not a git repository" }
    }

    $Upstream = & git -C $RootDir rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Upstream)) {
        return [PSCustomObject]@{ Status = "unknown"; Policy = "git upstream"; Relation = "no upstream configured" }
    }

    & git -C $RootDir fetch --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        return [PSCustomObject]@{ Status = "unknown"; Policy = $Upstream; Relation = "fetch failed" }
    }

    $Counts = & git -C $RootDir rev-list --left-right --count "HEAD...@{u}" 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Counts)) {
        return [PSCustomObject]@{ Status = "unknown"; Policy = $Upstream; Relation = "compare failed" }
    }

    $Parts = ([string]$Counts).Trim() -split "\s+"
    if ($Parts.Count -lt 2) {
        return [PSCustomObject]@{ Status = "unknown"; Policy = $Upstream; Relation = "compare failed" }
    }

    $Ahead = [int]$Parts[0]
    $Behind = [int]$Parts[1]
    if ($Behind -gt 0) {
        $Relation = if ($Ahead -gt 0) { "$Behind behind, $Ahead ahead" } else { "$Behind behind" }
        return [PSCustomObject]@{ Status = "outdated"; Policy = $Upstream; Relation = $Relation }
    }

    if ($Ahead -gt 0) {
        return [PSCustomObject]@{ Status = "ok"; Policy = $Upstream; Relation = "$Ahead ahead" }
    }

    return [PSCustomObject]@{ Status = "ok"; Policy = $Upstream; Relation = "current" }
}

function Get-WingetPackageId {
    param([string]$ComponentId)

    $Package = $WingetManagedPackages | Where-Object { $_.ComponentId -eq $ComponentId } | Select-Object -First 1
    if ($Package) {
        return $Package.Id
    }

    return ""
}

function New-Msys2CommandRow {
    param(
        [string]$Id,
        [string]$Name,
        [string[]]$Commands
    )

    $Missing = @($Commands | Where-Object { -not (Test-Msys2Command $_) })
    if ($Missing.Count -eq 0) {
        return New-ComponentRow "ok" "package" "msys2" "local" $Id $Name "pacman" "present"
    }

    return New-ComponentRow "missing" "package" "msys2" "local" $Id $Name "pacman" "" "-" "-" "install" $Id
}

function New-Msys2ToolRow {
    param(
        [string]$Id,
        [string]$Name,
        [string[]]$Commands
    )

    $Missing = @($Commands | Where-Object { -not (Test-Msys2Command $_) })
    if ($Missing.Count -eq 0) {
        return New-ComponentRow "ok" "tool" "msys2" "local" $Id $Name "msys2" "present"
    }

    return New-ComponentRow "missing" "tool" "msys2" "local" $Id $Name "msys2" "" "-" "-" "install" $Id
}

function Get-WingetUpgradeInfo {
    param([string]$PackageId)

    if (-not (Test-Command "winget")) {
        return [PSCustomObject]@{ Status = "unknown"; Available = ""; Relation = "winget unavailable" }
    }

    try {
        $Output = & winget upgrade --id $PackageId --exact --accept-source-agreements 2>&1
        $ExitCode = $LASTEXITCODE
    }
    catch {
        return [PSCustomObject]@{ Status = "unknown"; Available = ""; Relation = "winget failed" }
    }

    $Text = ($Output | Out-String).Trim()
    if ($Text -match "(?i)no available upgrade|no installed package|no package found|no applicable update|사용 가능한 업그레이드.*찾을 수 없습니다|최신 패키지 버전이 없습니다|설치된 패키지.*찾을 수 없습니다") {
        return [PSCustomObject]@{ Status = "ok"; Available = ""; Relation = "current" }
    }

    foreach ($Line in ($Text -split "(`r`n|`n|`r)")) {
        if ($Line -notmatch [regex]::Escape($PackageId)) {
            continue
        }

        $Tokens = @($Line.Trim() -split "\s+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $IdIndex = [Array]::IndexOf($Tokens, $PackageId)
        if ($IdIndex -ge 0 -and $Tokens.Count -gt ($IdIndex + 2)) {
            return [PSCustomObject]@{ Status = "outdated"; Available = $Tokens[$IdIndex + 2]; Relation = "update available" }
        }
    }

    if ($ExitCode -eq 0 -and $Text) {
        return [PSCustomObject]@{ Status = "unknown"; Available = ""; Relation = "winget output unparsed" }
    }

    return [PSCustomObject]@{ Status = "unknown"; Available = ""; Relation = "winget check failed" }
}

function Add-UpdateInfo {
    param([object[]]$Rows)

    foreach ($Row in $Rows) {
        if ($Row.Id -eq "repo-dotfiles" -and $Row.Status -eq "ok") {
            $Info = Get-GitUpdateInfo
            $Row.Policy = $Info.Policy
            $Row.Relation = $Info.Relation
            if ($Info.Status -eq "outdated") {
                $Row.Status = "outdated"
                $Row.ActionKind = "update"
                $Row.ActionTarget = "repo-dotfiles"
            }
            elseif ($Info.Status -eq "unknown") {
                $Row.Status = "unknown"
            }
            continue
        }

        if ($Row.Id -eq "package-pwsh") {
            if ($Row.Status -ne "ok") {
                continue
            }

            $CurrentVersion = ConvertTo-VersionOrNull $Row.Current
            $Release = Get-PowerShellStableReleaseInfo
            if ($Release.Status -ne "ok" -or $null -eq $Release.Version) {
                $Row.Status = "unknown"
                $Row.Policy = "github stable"
                $Row.Relation = $Release.Relation
                $Row.ActionKind = "update"
                $Row.ActionTarget = $Row.Id
                continue
            }

            $Row.Policy = "github $($Release.Tag)"
            if ($null -eq $CurrentVersion) {
                $Row.Status = "unknown"
                $Row.Relation = "version unknown"
                $Row.ActionKind = "update"
                $Row.ActionTarget = $Row.Id
            }
            elseif ($CurrentVersion -lt $Release.Version) {
                $Row.Status = "outdated"
                $Row.Relation = "update available"
                $Row.ActionKind = "update"
                $Row.ActionTarget = $Row.Id
            }
            else {
                $Row.Relation = "current"
            }
            continue
        }

        $WingetId = Get-WingetPackageId $Row.Id
        if ([string]::IsNullOrWhiteSpace($WingetId) -or $Row.Status -ne "ok") {
            continue
        }

        $Info = Get-WingetUpgradeInfo $WingetId
        if ($Info.Status -eq "outdated") {
            $Row.Status = "outdated"
            $Row.Policy = if ($Info.Available) { "winget $($Info.Available)" } else { "winget latest" }
            $Row.Relation = $Info.Relation
            $Row.ActionKind = "update"
            $Row.ActionTarget = $Row.Id
        }
        elseif ($Info.Status -eq "ok") {
            $Row.Policy = "winget latest"
            $Row.Relation = $Info.Relation
        }
        else {
            $Row.Status = "unknown"
            $Row.Policy = "winget latest"
            $Row.Relation = $Info.Relation
            $Row.ActionKind = "update"
            $Row.ActionTarget = $Row.Id
        }
    }

    return $Rows
}

function New-ComponentRow {
    param(
        [string]$Status,
        [string]$Category,
        [string]$Group,
        [string]$Scope,
        [string]$Id,
        [string]$Name,
        [string]$Method,
        [string]$Current = "",
        [string]$Policy = "-",
        [string]$Relation = "-",
        [string]$ActionKind = "none",
        [string]$ActionTarget = ""
    )

    [PSCustomObject]@{
        Status = $Status
        Category = $Category
        Group = $Group
        Scope = $Scope
        Id = $Id
        Name = $Name
        Method = $Method
        Current = $Current
        Policy = $Policy
        Relation = $Relation
        ActionKind = $ActionKind
        ActionTarget = $ActionTarget
    }
}

function New-CommandRow {
    param(
        [string]$Category,
        [string]$Group,
        [string]$Scope,
        [string]$Id,
        [string]$Name,
        [string]$Method,
        [string[]]$Commands,
        [string]$ActionTarget = $Id
    )

    $Missing = @($Commands | Where-Object { -not (Test-Command $_) })
    if ($Missing.Count -eq 0) {
        $Current = Get-CommandVersion $Commands[0]
        return New-ComponentRow "ok" $Category $Group $Scope $Id $Name $Method $Current
    }

    return New-ComponentRow "missing" $Category $Group $Scope $Id $Name $Method "" "-" "-" "install" $ActionTarget
}

function New-PowerShellRow {
    $Current = Get-PowerShellVersion
    $Policy = "github stable"

    if ([string]::IsNullOrWhiteSpace($Current)) {
        return New-ComponentRow "missing" "package" "system" "system" "package-pwsh" "PowerShell" "github" "" $Policy "not installed" "install" "package-pwsh"
    }

    $CurrentVersion = ConvertTo-VersionOrNull $Current
    if ($null -eq $CurrentVersion) {
        return New-ComponentRow "unknown" "package" "system" "system" "package-pwsh" "PowerShell" "github" $Current $Policy "version unknown"
    }

    return New-ComponentRow "ok" "package" "system" "system" "package-pwsh" "PowerShell" "github" $Current $Policy "installed"
}

function New-FileRow {
    param(
        [string]$Id,
        [string]$Name,
        [string]$Path,
        [string]$ActionTarget = $Id
    )

    if (Test-Path -Path $Path -PathType Leaf) {
        return New-ComponentRow "ok" "config" "chezmoi" "local" $Id $Name "chezmoi" "present"
    }

    return New-ComponentRow "missing" "config" "chezmoi" "local" $Id $Name "chezmoi" "" "-" "-" "sync" $ActionTarget
}

function New-Msys2Row {
    if (Test-Path -Path $Msys2Pacman -PathType Leaf) {
        return New-ComponentRow "ok" "package" "msys2" "system" "package-msys2" "MSYS2" "winget" "present"
    }

    return New-ComponentRow "missing" "package" "msys2" "system" "package-msys2" "MSYS2" "winget" "" "-" "-" "install" "package-msys2"
}

function New-Msys2ZshRow {
    if (-not (Test-Path -Path $Msys2Pacman -PathType Leaf)) {
        return New-ComponentRow "missing" "package" "msys2" "local" "package-zsh" "MSYS2 zsh" "pacman" "requires package-msys2" "-" "-" "install" "package-msys2"
    }

    if (Test-Path -Path $Msys2Zsh -PathType Leaf) {
        return New-ComponentRow "ok" "package" "msys2" "local" "package-zsh" "MSYS2 zsh" "pacman" (Get-Msys2CommandVersion $Msys2Zsh)
    }

    return New-ComponentRow "missing" "package" "msys2" "local" "package-zsh" "MSYS2 zsh" "pacman" "" "-" "-" "install" "package-zsh"
}

function New-DirRow {
    param(
        [string]$Category,
        [string]$Group,
        [string]$Scope,
        [string]$Id,
        [string]$Name,
        [string]$Method,
        [string]$Path,
        [string]$ActionTarget = ""
    )

    if (Test-Path -Path $Path -PathType Container) {
        return New-ComponentRow "ok" $Category $Group $Scope $Id $Name $Method "present"
    }

    $Current = if ($ActionTarget) { "managed by $ActionTarget" } else { "" }
    return New-ComponentRow "missing" $Category $Group $Scope $Id $Name $Method $Current
}

function New-FontRow {
    param(
        [string]$Id,
        [string]$Name,
        [string]$FileName
    )

    $FontPath = Join-Path (Join-Path (Get-LocalAppData) "Microsoft\Windows\Fonts") $FileName
    if (Test-Path -Path $FontPath -PathType Leaf) {
        return New-ComponentRow "ok" "font" "windows" "local" $Id $Name "registry" $FileName
    }

    return New-ComponentRow "missing" "font" "windows" "local" $Id $Name "registry" "" "-" "-" "install" $Id
}

function Get-NvimPluginRows {
    $NvimLazyDir = Join-Path (Get-Msys2HomePath) ".local\share\nvim-data\lazy"
    $Plugins = @(
        @{ Id = "plugin-nvim-lazy"; Name = "Neovim plugin: lazy.nvim"; Dir = "lazy.nvim" },
        @{ Id = "plugin-nvim-smart-splits"; Name = "Neovim plugin: smart-splits.nvim"; Dir = "smart-splits.nvim" },
        @{ Id = "plugin-nvim-blink-cmp"; Name = "Neovim plugin: blink.cmp"; Dir = "blink.cmp" },
        @{ Id = "plugin-nvim-neo-tree"; Name = "Neovim plugin: neo-tree.nvim"; Dir = "neo-tree.nvim" },
        @{ Id = "plugin-nvim-treesitter"; Name = "Neovim plugin: nvim-treesitter"; Dir = "nvim-treesitter" },
        @{ Id = "plugin-nvim-mason"; Name = "Neovim plugin: mason.nvim"; Dir = "mason.nvim" }
    )

    $Missing = 0
    $Rows = @()
    foreach ($Plugin in $Plugins) {
        $Path = Join-Path $NvimLazyDir $Plugin.Dir
        if (Test-Path -Path $Path -PathType Container) {
            $Rows += New-ComponentRow "ok" "plugin" "nvim" "local" $Plugin.Id $Plugin.Name "lazy.nvim" "present"
        }
        else {
            $Missing += 1
            $Rows += New-ComponentRow "missing" "plugin" "nvim" "local" $Plugin.Id $Plugin.Name "lazy.nvim" "managed by plugin-nvim" "-" "-" "install" "plugin-nvim"
        }
    }

    if ($Missing -eq 0) {
        $GroupRow = New-ComponentRow "ok" "plugin" "nvim" "local" "plugin-nvim" "Neovim plugins" "lazy.nvim" "$($Plugins.Count) present"
    }
    else {
        $GroupRow = New-ComponentRow "missing" "plugin" "nvim" "local" "plugin-nvim" "Neovim plugins" "lazy.nvim" "$Missing/$($Plugins.Count) missing" "-" "-" "install" "plugin-nvim"
    }

    return @($GroupRow) + $Rows
}

function Get-ZshPluginRows {
    $Msys2Home = Get-Msys2HomePath
    $AntidoteDir = Join-Path $Msys2Home ".antidote"
    $AntidoteHome = Join-Path $Msys2Home ".cache\antidote"
    $Plugins = @(
        @{ Id = "plugin-zsh-antidote"; Name = "Antidote"; Method = "git"; Kind = "file"; Path = (Join-Path $AntidoteDir "antidote.zsh") },
        @{ Id = "plugin-zsh-powerlevel10k"; Name = "zsh plugin: powerlevel10k"; Method = "antidote"; Kind = "dir"; Path = (Join-Path $AntidoteHome "github.com\romkatv\powerlevel10k") },
        @{ Id = "plugin-zsh-forgit"; Name = "zsh plugin: forgit"; Method = "antidote"; Kind = "dir"; Path = (Join-Path $AntidoteHome "github.com\wfxr\forgit") },
        @{ Id = "plugin-zsh-vi-mode"; Name = "zsh plugin: zsh-vi-mode"; Method = "antidote"; Kind = "dir"; Path = (Join-Path $AntidoteHome "github.com\jeffreytse\zsh-vi-mode") }
    )

    $Missing = 0
    $Rows = @()
    foreach ($Plugin in $Plugins) {
        $Exists = if ($Plugin.Kind -eq "file") {
            Test-Path -Path $Plugin.Path -PathType Leaf
        }
        else {
            Test-Path -Path $Plugin.Path -PathType Container
        }

        if ($Exists) {
            $Rows += New-ComponentRow "ok" "plugin" "zsh" "local" $Plugin.Id $Plugin.Name $Plugin.Method "present"
        }
        else {
            $Missing += 1
            $Rows += New-ComponentRow "missing" "plugin" "zsh" "local" $Plugin.Id $Plugin.Name $Plugin.Method "managed by plugin-zsh" "-" "-" "install" "plugin-zsh"
        }
    }

    if ($Missing -eq 0) {
        $GroupRow = New-ComponentRow "ok" "plugin" "zsh" "local" "plugin-zsh" "zsh plugins" "antidote" "$($Plugins.Count) present"
    }
    else {
        $GroupRow = New-ComponentRow "missing" "plugin" "zsh" "local" "plugin-zsh" "zsh plugins" "antidote" "$Missing/$($Plugins.Count) missing" "-" "-" "install" "plugin-zsh"
    }

    return @($GroupRow) + $Rows
}

function Get-ComponentRows {
    param([switch]$CheckUpdates)

    Update-ProcessPath

    $Chezmoi = Resolve-Chezmoi
    $Msys2Home = Get-Msys2HomePath
    $Rows = @()

    $RepoCurrent = Get-RepoVersion
    if ($RepoCurrent) {
        $Rows += New-ComponentRow "ok" "repo" "git" "local" "repo-dotfiles" "dotfiles repo" "git" $RepoCurrent
    }
    else {
        $Rows += New-ComponentRow "missing" "repo" "git" "local" "repo-dotfiles" "dotfiles repo" "git" "" "-" "-" "install" "repo-dotfiles"
    }

    $Rows += New-CommandRow "package" "system" "system" "package-git" "git" "package" @("git")
    $Rows += New-CommandRow "package" "system" "system" "package-chezmoi" "chezmoi" "package" @($Chezmoi)
    $Rows += New-Msys2Row
    $Rows += New-Msys2ZshRow
    $Rows += New-PowerShellRow
    $Rows += New-Msys2CommandRow "package-nvim" "MSYS2 nvim" @("nvim")
    $Rows += New-Msys2CommandRow "package-node" "MSYS2 Node.js" @("node", "npm")
    $Rows += New-CommandRow "package" "system" "system" "package-wezterm" "WezTerm" "package" @("wezterm")
    $Rows += New-CommandRow "dependency" "rustup" "local" "dependency-rust" "Rust toolchain" "rustup" @("rustc", "cargo")
    $Rows += New-Msys2ToolRow "tool-zoxide" "MSYS2 zoxide" @("zoxide")
    $Rows += New-Msys2ToolRow "tool-direnv" "MSYS2 direnv" @("direnv")

    $Rows += New-FileRow "config-nvim" "MSYS2 Neovim config" (Join-Path $Msys2Home ".config\nvim\init.lua")
    $Rows += New-FileRow "config-nvim-lite" "MSYS2 Neovim lite config" (Join-Path $Msys2Home ".config\nvim-lite\init.lua")
    $Rows += New-FileRow "config-tmux" "MSYS2 tmux config" (Join-Path $Msys2Home ".config\tmux\tmux.conf")
    $Rows += New-FileRow "config-zshrc" "MSYS2 zshrc" (Join-Path $Msys2Home ".zshrc")
    $Rows += New-FileRow "config-zshenv" "MSYS2 zshenv" (Join-Path $Msys2Home ".zshenv")
    $Rows += New-FileRow "config-zsh-plugins" "MSYS2 zsh plugin manifest" (Join-Path $Msys2Home ".config\zsh\plugins.txt")
    $Rows += New-FileRow "config-p10k" "MSYS2 Powerlevel10k config" (Join-Path $Msys2Home ".p10k.zsh")
    $Rows += New-FileRow "config-wezterm" "managed WezTerm config" (Join-Path $HOME ".config\wezterm\wezterm.lua")
    $Rows += New-FileRow "config-wezterm-smart-splits" "WezTerm smart-splits config" (Join-Path $HOME ".config\wezterm\user\smart_splits.lua") "config-wezterm"

    $Rows += New-FontRow "font-red-hat-mono" "Red Hat Mono" "RedHatMono-Regular.ttf"
    $Rows += New-FontRow "font-d2coding-ligature" "D2CodingLigature Nerd Font" "D2CodingLigatureNerdFont-Regular.ttf"
    $Rows += Get-ZshPluginRows
    $Rows += Get-NvimPluginRows

    if ($CheckUpdates) {
        $Rows = @(Add-UpdateInfo -Rows $Rows)
    }

    $NeedsActionCount = @($Rows | Where-Object { $_.Status -eq "missing" -or $_.Status -eq "unknown" -or $_.Status -eq "outdated" }).Count
    $MissingOrUnknownCount = @($Rows | Where-Object { $_.Status -eq "missing" -or $_.Status -eq "unknown" }).Count
    $OutdatedCount = @($Rows | Where-Object { $_.Status -eq "outdated" }).Count
    if ($NeedsActionCount -eq 0) {
        $AllRow = New-ComponentRow "ok" "all" "setup" "local" "all-install" "complete dotfiles setup" "installer" "all present"
    }
    elseif ($CheckUpdates -and $OutdatedCount -gt 0 -and $MissingOrUnknownCount -eq 0) {
        $AllRow = New-ComponentRow "outdated" "all" "setup" "local" "all-updates" "managed updates" "installer" "$OutdatedCount update available" "-" "updates available" "update" "all-updates"
    }
    else {
        $AllRow = New-ComponentRow "missing" "all" "setup" "local" "all-install" "complete dotfiles setup" "installer" "$NeedsActionCount need action" "-" "-" "install" "all-install"
    }

    return @($AllRow) + $Rows
}

function ConvertTo-RawRow {
    param([object]$Row)

    @(
        $Row.Status,
        $Row.Category,
        $Row.Group,
        $Row.Scope,
        $Row.Id,
        $Row.Name,
        $Row.Method,
        $Row.Current,
        $Row.Policy,
        $Row.Relation,
        $Row.ActionKind,
        $Row.ActionTarget
    ) -join "|"
}

function Write-ComponentRaw {
    param([switch]$CheckUpdates)

    Get-ComponentRows -CheckUpdates:$CheckUpdates | ForEach-Object { ConvertTo-RawRow $_ }
}

function Get-DisplayValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "-"
    }

    return $Value
}

function Write-ComponentTable {
    param([switch]$CheckUpdates)

    $Format = "{0,-8} {1,-12} {2,-12} {3,-7} {4,-28} {5,-34} {6,-14} {7,-16} {8,-36} {9,-24} {10}"
    $Format -f "STATUS", "CATEGORY", "GROUP", "SCOPE", "ID", "COMPONENT", "METHOD", "CURRENT", "POLICY", "RELATION", "ACTION"
    $Format -f "------", "--------", "-----", "-----", "--", "---------", "------", "-------", "------", "--------", "------"

    Get-ComponentRows -CheckUpdates:$CheckUpdates | ForEach-Object {
        $Action = if ($_.ActionKind -eq "none" -or [string]::IsNullOrWhiteSpace($_.ActionTarget)) {
            "-"
        }
        else {
            "bin/dot.ps1 update --$($_.ActionKind) $($_.ActionTarget)"
        }

        $Format -f $_.Status, $_.Category, $_.Group, $_.Scope, $_.Id, $_.Name, $_.Method,
            (Get-DisplayValue $_.Current), (Get-DisplayValue $_.Policy), (Get-DisplayValue $_.Relation), $Action
    }
}

function Invoke-ChezmoiSync {
    param([string]$ComponentId = "")

    Update-ProcessPath

    $Chezmoi = Resolve-Chezmoi
    if (-not (Test-Command $Chezmoi)) {
        Write-DotfilesLog "installing chezmoi for config sync"
        Invoke-PackageAction "install" "package-chezmoi"
        Update-ProcessPath
        $Chezmoi = Resolve-Chezmoi
    }

    if (-not (Test-Command $Chezmoi)) {
        Write-DotfilesLog "chezmoi is required for config sync and could not be installed"
        exit 1
    }

    $WindowsTargetNames = @(Get-WindowsChezmoiTargetsForComponent $ComponentId)
    $Msys2TargetNames = @(Get-Msys2ChezmoiTargetsForComponent $ComponentId)

    if (-not [string]::IsNullOrWhiteSpace($ComponentId) -and $WindowsTargetNames.Count -eq 0 -and $Msys2TargetNames.Count -eq 0) {
        Write-DotfilesLog "config sync is not supported for component: $ComponentId"
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($ComponentId)) {
        Backup-StaleWindowsConfigPaths
    }

    if ($WindowsTargetNames.Count -gt 0) {
        $WindowsTargets = @($WindowsTargetNames | ForEach-Object { Convert-ChezmoiTargetToPath -Root $HOME -Target $_ })
        Ensure-ChezmoiTargetParents -Paths $WindowsTargets
        Write-DotfilesLog "syncing Windows-native chezmoi targets to Windows home"
        & $Chezmoi --source $SourceDir --destination $HOME apply --force @WindowsTargets
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }

    $Msys2Home = Get-Msys2HomePath
    if ($Msys2TargetNames.Count -gt 0) {
        New-Item -ItemType Directory -Path $Msys2Home -Force | Out-Null
        $Msys2Targets = @($Msys2TargetNames | ForEach-Object { Convert-ChezmoiTargetToPath -Root $Msys2Home -Target $_ })
        Ensure-ChezmoiTargetParents -Paths $Msys2Targets
        Write-DotfilesLog "syncing MSYS2 chezmoi targets to MSYS2 home $Msys2Home"
        & $Chezmoi --source $SourceDir --destination $Msys2Home apply --force @Msys2Targets
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
}

function Invoke-PackageAction {
    param(
        [string]$ActionName,
        [string]$ComponentId = ""
    )

    $PackageScript = Join-Path (Join-Path $RootDir "packages") "windows.ps1"
    $ScriptAction = if ($ActionName -eq "update") { "upgrade" } else { "install" }
    & $PackageScript $ScriptAction $ComponentId
    Update-ProcessPath
}

function Invoke-ZshAction {
    param([string]$ActionName)

    $ZshScript = Join-Path (Join-Path $RootDir "scripts") "install-msys2-zsh.ps1"
    $ScriptAction = if ($ActionName -eq "update") { "update" } else { "install" }
    & $ZshScript $ScriptAction
}

function Invoke-Msys2PackageAction {
    param([string]$ComponentId)

    $PackageName = switch ($ComponentId) {
        "package-nvim" { "mingw-w64-ucrt-x86_64-neovim" }
        "package-node" { "mingw-w64-ucrt-x86_64-nodejs" }
        default {
            Write-DotfilesLog "MSYS2 package install is not supported for component: $ComponentId"
            exit 1
        }
    }

    $Bash = Resolve-Msys2Command "bash"
    if ([string]::IsNullOrWhiteSpace($Bash)) {
        Write-DotfilesLog "MSYS2 bash is required"
        exit 1
    }

    Write-DotfilesLog "installing MSYS2 package $PackageName"
    & $Bash -lc "pacman -Sy --needed --noconfirm $PackageName"
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Invoke-ToolAction {
    param(
        [string]$ActionName,
        [string]$ComponentId
    )

    $ScriptAction = if ($ActionName -eq "update") { "update" } else { "install" }
    $ToolName = switch ($ComponentId) {
        "tool-zoxide" { "zoxide" }
        "tool-direnv" { "direnv" }
        default { $ComponentId }
    }

    Invoke-Msys2RepoScript "scripts/install-user-tools.sh" @($ScriptAction, $ToolName)
}

function Invoke-FontAction {
    param([string]$ComponentId)

    $FontScript = Join-Path (Join-Path $RootDir "scripts") "install-fonts.ps1"
    & $FontScript install $ComponentId
}

function Invoke-NvimPluginAction {
    param(
        [string]$ActionName,
        [string]$ComponentId
    )

    $ScriptAction = if ($ActionName -eq "update") { "update" } else { "install" }
    Invoke-Msys2RepoScript "scripts/install-neovim-plugins.sh" @($ScriptAction, $ComponentId)
}

function Invoke-ZshPluginAction {
    param([string]$ActionName)

    if ($ActionName -eq "update") {
        Invoke-Msys2RepoScript "scripts/install-antidote.sh" @("update")
        return
    }

    Invoke-Msys2RepoScript "scripts/install-antidote.sh" @("install")
    Invoke-Msys2RepoScript "scripts/install-antidote.sh" @("update")
}

function Invoke-AllUpdates {
    $Rows = @(Get-ComponentRows -CheckUpdates | Where-Object {
            $_.Status -eq "outdated" -and $_.ActionKind -eq "update" -and -not [string]::IsNullOrWhiteSpace($_.ActionTarget)
        })

    if ($Rows.Count -eq 0) {
        Write-DotfilesLog "no managed updates available"
        return
    }

    $Targets = @($Rows | ForEach-Object { $_.ActionTarget } | Select-Object -Unique)
    foreach ($Target in $Targets) {
        Write-DotfilesLog "updating managed component: $Target"
        Invoke-ComponentAction "update" $Target -NoStatus
    }
}

function Invoke-ComponentAction {
    param(
        [string]$ActionName,
        [string]$ComponentId,
        [switch]$NoStatus
    )

    Write-DotfilesLog "$ActionName component: $ComponentId"

    switch -Regex ($ComponentId) {
        "^all-updates$" {
            if ($ActionName -ne "update") {
                Write-DotfilesLog "$ActionName is not supported for component: $ComponentId"
                exit 1
            }
            Invoke-AllUpdates
            break
        }
        "^all-install$" { & $BootstrapScript; break }
        "^repo-dotfiles$" { Invoke-GitRoot pull --ff-only; break }
        "^package-zsh$" { Invoke-ZshAction $ActionName; break }
        "^package-(nvim|node)$" { Invoke-Msys2PackageAction $ComponentId; break }
        "^(package-|dependency-rust)" { Invoke-PackageAction $ActionName $ComponentId; break }
        "^tool-" { Invoke-ToolAction $ActionName $ComponentId; break }
        "^font-" { Invoke-FontAction $ComponentId; break }
        "^plugin-zsh$" { Invoke-ChezmoiSync; Invoke-ZshPluginAction $ActionName; break }
        "^plugin-zsh-" {
            Write-DotfilesLog "$ActionName is managed by group component: plugin-zsh"
            exit 1
        }
        "^plugin-nvim$" { Invoke-NvimPluginAction $ActionName $ComponentId; break }
        "^plugin-nvim-" {
            Write-DotfilesLog "$ActionName is managed by group component: plugin-nvim"
            exit 1
        }
        "^config-" {
            Invoke-ChezmoiSync $ComponentId
            break
        }
        default {
            Write-DotfilesLog "$ActionName is not supported for component: $ComponentId"
            exit 1
        }
    }

    if (-not $NoStatus) {
        Write-DotfilesLog "component status"
        Write-ComponentTable
    }
}

function Invoke-UpdateCommand {
    param([string[]]$UpdateArgs)

    $Action = "status"
    $ComponentId = ""

    for ($Index = 0; $Index -lt $UpdateArgs.Count; $Index++) {
        switch ($UpdateArgs[$Index]) {
            "--check" { $Action = "check" }
            "check" { $Action = "check" }
            "--check-updates" { $Action = "check-updates" }
            "check-updates" { $Action = "check-updates" }
            "--raw" { $Action = "raw" }
            "raw" { $Action = "raw" }
            "--install" {
                $Action = "install"
                $Index += 1
                $ComponentId = $UpdateArgs[$Index]
            }
            "install" {
                $Action = "install"
                $Index += 1
                $ComponentId = $UpdateArgs[$Index]
            }
            "--update" {
                $Action = "update"
                $Index += 1
                $ComponentId = $UpdateArgs[$Index]
            }
            "update" {
                $Action = "update"
                $Index += 1
                $ComponentId = $UpdateArgs[$Index]
            }
            "--sync" {
                $Action = "sync"
                $Index += 1
                $ComponentId = $UpdateArgs[$Index]
            }
            "sync" {
                $Action = "sync"
                $Index += 1
                $ComponentId = $UpdateArgs[$Index]
            }
            "--build" {
                $Action = "build"
                $Index += 1
                $ComponentId = $UpdateArgs[$Index]
            }
            "build" {
                $Action = "build"
                $Index += 1
                $ComponentId = $UpdateArgs[$Index]
            }
            default {
                Show-Usage
                exit 1
            }
        }
    }

    switch ($Action) {
        "raw" { Write-ComponentRaw }
        "check" {
            Write-DotfilesLog "component status"
            Write-ComponentTable
        }
        "check-updates" {
            Write-DotfilesLog "checking managed updates"
            Write-ComponentTable -CheckUpdates
        }
        "status" {
            if (-not (Test-Command "git")) {
                Write-DotfilesLog "git is required for update"
                exit 1
            }

            Write-DotfilesLog "updating repository"
            Invoke-GitRoot pull --ff-only
            Write-DotfilesLog "component status"
            Write-ComponentTable
        }
        default {
            if ([string]::IsNullOrWhiteSpace($ComponentId)) {
                Write-DotfilesLog "$Action requires a component id"
                exit 1
            }

            Invoke-ComponentAction $Action $ComponentId
        }
    }
}

function Invoke-Tui {
    $ManifestPath = Join-Path (Join-Path $RootDir "tools\dot-tui") "Cargo.toml"
    $ReleaseBinary = Join-Path (Join-Path $RootDir "tools\dot-tui\target\release") "dot-tui.exe"
    $DebugBinary = Join-Path (Join-Path $RootDir "tools\dot-tui\target\debug") "dot-tui.exe"

    if (Test-Path -Path $ReleaseBinary -PathType Leaf) {
        & $ReleaseBinary $RootDir
    }
    elseif (Test-Path -Path $DebugBinary -PathType Leaf) {
        & $DebugBinary $RootDir
    }
    elseif (Test-Command "cargo") {
        Write-DotfilesLog "building and running Ratatui dashboard"
        cargo run --quiet --manifest-path $ManifestPath -- $RootDir
    }
    else {
        Write-DotfilesLog "cargo is required to build the Ratatui dashboard"
        Write-DotfilesLog "run: .\bin\dot.ps1 update --install dependency-rust"
        exit 1
    }
}

switch ($CommandName) {
    "bootstrap" { & $BootstrapScript @CommandArgs }
    "install" { & $BootstrapScript @CommandArgs }
    "tui" { Invoke-Tui }
    "sync" {
        Invoke-ChezmoiSync
    }
    "dev-ref" { Invoke-DevRefCommand -Args $CommandArgs }
    "dev-apply" { Invoke-DevApply }
    "doctor" {
        if ($CommandArgs -contains "--fix" -or $CommandArgs -contains "fix") {
            & $BootstrapScript
        }
        else {
            & $BootstrapScript -CheckOnly
        }
    }
    "update" { Invoke-UpdateCommand -UpdateArgs $CommandArgs }
    "help" { Show-Usage }
    "-h" { Show-Usage }
    "--help" { Show-Usage }
    default {
        Show-Usage
        exit 1
    }
}
