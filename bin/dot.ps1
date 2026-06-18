param(
    [Parameter(Position = 0)]
    [string]$CommandName = "help",
    [switch]$Raw,
    [switch]$Check,
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
$PowerShellTargetVersion = [Version]"7.6.3"
$PowerShellReleaseUrl = "https://github.com/PowerShell/PowerShell/releases/tag/v7.6.3"

if ($Raw) { $CommandArgs += "--raw" }
if ($Check) { $CommandArgs += "--check" }
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
    $Dirty = & git -C $RootDir status --porcelain
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

    $IsRepo = & git -C $DevDir rev-parse --is-inside-work-tree 2>$null
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

    $RootHead = & git -C $RootDir rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($RootHead)) {
        Write-DotfilesLog "failed to resolve root HEAD"
        exit 1
    }

    $Deleted = @(& git -C $DevDir diff --name-only --diff-filter=D $RootHead --)
    $Changed = @(& git -C $DevDir diff --name-only --diff-filter=ACMRT $RootHead --)
    $Untracked = @(& git -C $DevDir ls-files --others --exclude-standard)

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

    $IsRepo = & git -C $RootDir rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $IsRepo -ne "true") {
        return ""
    }

    $Branch = & git -C $RootDir rev-parse --abbrev-ref HEAD 2>$null
    $Sha = & git -C $RootDir rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $Branch -and $Sha) {
        return "$Branch@$Sha"
    }

    return ""
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
    $Policy = ">= $PowerShellTargetVersion ($PowerShellReleaseUrl)"

    if ([string]::IsNullOrWhiteSpace($Current)) {
        return New-ComponentRow "missing" "package" "system" "system" "package-pwsh" "PowerShell" "winget" "" $Policy "not installed" "install" "package-pwsh"
    }

    $CurrentVersion = ConvertTo-VersionOrNull $Current
    if ($null -eq $CurrentVersion) {
        return New-ComponentRow "unknown" "package" "system" "system" "package-pwsh" "PowerShell" "winget" $Current $Policy "version unknown" "update" "package-pwsh"
    }

    if ($CurrentVersion -lt $PowerShellTargetVersion) {
        return New-ComponentRow "outdated" "package" "system" "system" "package-pwsh" "PowerShell" "winget" $Current $Policy "behind target" "update" "package-pwsh"
    }

    return New-ComponentRow "ok" "package" "system" "system" "package-pwsh" "PowerShell" "winget" $Current $Policy "meets target"
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
    $NvimLazyDir = Join-Path (Get-LocalAppData) "nvim-data\lazy"
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
            $Rows += New-ComponentRow "missing" "plugin" "nvim" "local" $Plugin.Id $Plugin.Name "lazy.nvim" "managed by plugin-nvim"
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

function Get-ComponentRows {
    $Chezmoi = Resolve-Chezmoi
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
    $Rows += New-PowerShellRow
    $Rows += New-CommandRow "package" "system" "system" "package-nvim" "nvim" "package" @("nvim")
    $Rows += New-CommandRow "package" "system" "system" "package-wezterm" "WezTerm" "package" @("wezterm")
    $Rows += New-CommandRow "dependency" "rustup" "local" "dependency-rust" "Rust toolchain" "rustup" @("rustc", "cargo")
    $Rows += New-CommandRow "tool" "user-bin" "local" "tool-zoxide" "zoxide" "winget" @("zoxide")
    $Rows += New-CommandRow "tool" "user-bin" "local" "tool-direnv" "direnv" "winget" @("direnv")

    $Rows += New-FileRow "config-nvim" "managed Neovim config" (Join-Path $HOME ".config\nvim\init.lua")
    $Rows += New-FileRow "config-nvim-windows" "Windows Neovim config" (Join-Path (Get-LocalAppData) "nvim\init.lua")
    $Rows += New-FileRow "config-wezterm" "managed WezTerm config" (Join-Path $HOME ".config\wezterm\wezterm.lua")
    $Rows += New-FileRow "config-wezterm-smart-splits" "WezTerm smart-splits config" (Join-Path $HOME ".config\wezterm\user\smart_splits.lua") "config-wezterm"

    $Rows += New-FontRow "font-red-hat-mono" "Red Hat Mono" "RedHatMono-Regular.ttf"
    $Rows += New-FontRow "font-d2coding-ligature" "D2CodingLigature Nerd Font" "D2CodingLigatureNerdFont-Regular.ttf"
    $Rows += Get-NvimPluginRows

    $MissingCount = @($Rows | Where-Object { $_.Status -eq "missing" -or $_.Status -eq "unknown" -or $_.Status -eq "outdated" }).Count
    if ($MissingCount -eq 0) {
        $AllRow = New-ComponentRow "ok" "all" "setup" "local" "all-install" "complete dotfiles setup" "installer" "all present"
    }
    else {
        $AllRow = New-ComponentRow "missing" "all" "setup" "local" "all-install" "complete dotfiles setup" "installer" "$MissingCount need action" "-" "-" "install" "all-install"
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
    Get-ComponentRows | ForEach-Object { ConvertTo-RawRow $_ }
}

function Get-DisplayValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "-"
    }

    return $Value
}

function Write-ComponentTable {
    $Format = "{0,-8} {1,-12} {2,-12} {3,-7} {4,-28} {5,-34} {6,-14} {7,-16} {8,-36} {9,-24} {10}"
    $Format -f "STATUS", "CATEGORY", "GROUP", "SCOPE", "ID", "COMPONENT", "METHOD", "CURRENT", "POLICY", "RELATION", "ACTION"
    $Format -f "------", "--------", "-----", "-----", "--", "---------", "------", "-------", "------", "--------", "------"

    Get-ComponentRows | ForEach-Object {
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

function Sync-DirectoryContents {
    param(
        [string]$Source,
        [string]$Target,
        [string]$Description
    )

    if (-not (Test-Path -Path $Source -PathType Container)) {
        Write-DotfilesLog "skipping $Description because source is missing: $Source"
        return
    }

    $Parent = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $Parent -Force | Out-Null

    if (-not (Test-Path -Path $Target -PathType Container)) {
        try {
            Write-DotfilesLog "linking $Description"
            New-Item -ItemType Junction -Path $Target -Target $Source -Force | Out-Null
            return
        }
        catch {
            Write-DotfilesLog "failed to create junction for $Description; copying files instead"
            New-Item -ItemType Directory -Path $Target -Force | Out-Null
        }
    }

    Write-DotfilesLog "syncing $Description"
    Get-ChildItem -Path $Source -Force | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $Target -Recurse -Force
    }
}

function Sync-WindowsConfigPaths {
    $ManagedNvimConfig = Join-Path $HOME ".config\nvim"
    $WindowsNvimConfig = Join-Path (Get-LocalAppData) "nvim"
    Sync-DirectoryContents -Source $ManagedNvimConfig -Target $WindowsNvimConfig -Description "Windows Neovim config"
}

function Invoke-ChezmoiSync {
    $Chezmoi = Resolve-Chezmoi
    if (-not (Test-Command $Chezmoi)) {
        Write-DotfilesLog "chezmoi is required for config sync"
        exit 1
    }

    Write-DotfilesLog "syncing chezmoi source"
    & $Chezmoi --source $SourceDir apply
}

function Invoke-PackageAction {
    param(
        [string]$ActionName,
        [string]$ComponentId = ""
    )

    $PackageScript = Join-Path (Join-Path $RootDir "packages") "windows.ps1"
    $ScriptAction = if ($ActionName -eq "update") { "upgrade" } else { "install" }
    & $PackageScript $ScriptAction $ComponentId
}

function Invoke-ToolAction {
    param([string]$ActionName)

    $ToolsScript = Join-Path (Join-Path $RootDir "scripts") "install-user-tools.ps1"
    $ScriptAction = if ($ActionName -eq "update") { "update" } else { "install" }
    & $ToolsScript $ScriptAction
}

function Invoke-FontAction {
    $FontScript = Join-Path (Join-Path $RootDir "scripts") "install-fonts.ps1"
    & $FontScript install
}

function Invoke-NvimPluginAction {
    param([string]$ActionName)

    $NvimScript = Join-Path (Join-Path $RootDir "scripts") "install-neovim-plugins.ps1"
    $ScriptAction = if ($ActionName -eq "update") { "update" } else { "install" }
    & $NvimScript $ScriptAction
}

function Invoke-ComponentAction {
    param(
        [string]$ActionName,
        [string]$ComponentId
    )

    Write-DotfilesLog "$ActionName component: $ComponentId"

    switch -Regex ($ComponentId) {
        "^all-install$" { & $BootstrapScript; break }
        "^repo-dotfiles$" { git -C $RootDir pull --ff-only; break }
        "^(package-|dependency-rust)" { Invoke-PackageAction $ActionName $ComponentId; break }
        "^tool-" { Invoke-ToolAction $ActionName; break }
        "^font-" { Invoke-FontAction; break }
        "^plugin-nvim$" { Invoke-NvimPluginAction $ActionName; break }
        "^plugin-nvim-" {
            Write-DotfilesLog "$ActionName is managed by group component: plugin-nvim"
            exit 1
        }
        "^config-nvim-windows$" { Sync-WindowsConfigPaths; break }
        "^config-" {
            Invoke-ChezmoiSync
            if ($ComponentId -eq "config-nvim") {
                Sync-WindowsConfigPaths
            }
            break
        }
        default {
            Write-DotfilesLog "$ActionName is not supported for component: $ComponentId"
            exit 1
        }
    }

    Write-DotfilesLog "component status"
    Write-ComponentTable
}

function Invoke-UpdateCommand {
    param([string[]]$UpdateArgs)

    $Action = "status"
    $ComponentId = ""

    for ($Index = 0; $Index -lt $UpdateArgs.Count; $Index++) {
        switch ($UpdateArgs[$Index]) {
            "--check" { $Action = "check" }
            "check" { $Action = "check" }
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
        "status" {
            if (-not (Test-Command "git")) {
                Write-DotfilesLog "git is required for update"
                exit 1
            }

            Write-DotfilesLog "updating repository"
            git -C $RootDir pull --ff-only
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
        Sync-WindowsConfigPaths
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
