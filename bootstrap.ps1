param(
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceDir = if ($env:DOTFILES_SOURCE_DIR) { $env:DOTFILES_SOURCE_DIR } else { Join-Path $RootDir "home" }
$RepoLocalDir = Join-Path (Join-Path $RootDir ".local") "bin"
$RepoChezmoi = Join-Path $RepoLocalDir "chezmoi"
$RepoChezmoiExe = Join-Path $RepoLocalDir "chezmoi.exe"

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

function Update-ProcessPath {
    $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $PathParts = @($MachinePath, $UserPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($PathParts.Count -gt 0) {
        $env:Path = $PathParts -join ";"
    }
}

function Get-LocalAppData {
    if ($env:LOCALAPPDATA) {
        return $env:LOCALAPPDATA
    }

    return Join-Path $HOME "AppData\Local"
}

function Mark-Missing {
    param([string]$Message)

    Write-DotfilesLog "missing: $Message"
    $script:Failed = $true
}

function Mark-Warning {
    param([string]$Message)

    Write-DotfilesLog "warning: $Message"
}

function Set-InstallNeed {
    param([string]$InstallGroup)

    switch ($InstallGroup) {
        "packages" { $script:NeedPackages = $true }
        "tools" { $script:NeedTools = $true }
        "none" { }
    }
}

function Test-CommandStatus {
    param(
        [string]$Name,
        [string]$InstallGroup,
        [string]$Label = $Name
    )

    if (Test-Command $Name) {
        Write-DotfilesLog "ok: command $Label"
        return
    }

    Mark-Missing "command $Label"
    Set-InstallNeed $InstallGroup
}

function Test-FileStatus {
    param(
        [string]$Path,
        [string]$Description
    )

    if (Test-Path -Path $Path -PathType Leaf) {
        Write-DotfilesLog "ok: $Description"
        return
    }

    Mark-Missing $Description
    $script:NeedSync = $true
}

function Test-WindowsConfigFileStatus {
    param(
        [string]$Path,
        [string]$Description
    )

    if (Test-Path -Path $Path -PathType Leaf) {
        Write-DotfilesLog "ok: $Description"
        return
    }

    Mark-Missing $Description
    $script:NeedWindowsConfigSync = $true
}

function Sync-DirectoryContents {
    param(
        [string]$Source,
        [string]$Target,
        [string]$Description
    )

    if (-not (Test-Path -Path $Source -PathType Container)) {
        Mark-Warning "skipping $Description because source is missing: $Source"
        return
    }

    $Parent = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $Parent -Force | Out-Null

    if (-not (Test-Path -Path $Target -PathType Container)) {
        try {
            Write-DotfilesLog "fix: linking $Description"
            New-Item -ItemType Junction -Path $Target -Target $Source -Force | Out-Null
            return
        }
        catch {
            Write-DotfilesLog "warning: failed to create junction for $Description; copying files instead"
            New-Item -ItemType Directory -Path $Target -Force | Out-Null
        }
    }

    $TargetItem = Get-Item -Path $Target -ErrorAction SilentlyContinue
    if ($TargetItem -and (($TargetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        Write-DotfilesLog "ok: $Description link"
        return
    }

    Write-DotfilesLog "fix: syncing $Description"
    Get-ChildItem -Path $Source -Force | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $Target -Recurse -Force
    }
}

function Sync-WindowsConfigPaths {
    $ManagedNvimConfig = Join-Path $HOME ".config\nvim"
    $WindowsNvimConfig = Join-Path (Get-LocalAppData) "nvim"

    Sync-DirectoryContents -Source $ManagedNvimConfig -Target $WindowsNvimConfig -Description "Windows Neovim config"
}

function Test-FontStatus {
    $FontDir = Join-Path (Get-LocalAppData) "Microsoft\Windows\Fonts"
    $FontChecks = @(
        @{ Pattern = "RedHatMono-Regular.ttf"; Name = "Red Hat Mono" },
        @{ Pattern = "D2CodingLigatureNerdFont-Regular.ttf"; Name = "D2CodingLigature Nerd Font" }
    )

    foreach ($Font in $FontChecks) {
        $Matches = @()
        if (Test-Path -Path $FontDir -PathType Container) {
            $Matches = @(Get-ChildItem -Path $FontDir -Filter $Font.Pattern -File -ErrorAction SilentlyContinue)
        }

        if ($Matches.Count -gt 0) {
            Write-DotfilesLog "ok: font $($Font.Name)"
        }
        else {
            Mark-Missing "font $($Font.Name)"
            $script:NeedFonts = $true
        }
    }
}

function Test-NeovimPluginsStatus {
    $NvimLazyDir = Join-Path (Get-LocalAppData) "nvim-data\lazy"
    $Plugins = @(
        "lazy.nvim",
        "smart-splits.nvim",
        "blink.cmp",
        "neo-tree.nvim",
        "nvim-treesitter",
        "mason.nvim"
    )

    foreach ($Plugin in $Plugins) {
        if (Test-Path -Path (Join-Path $NvimLazyDir $Plugin) -PathType Container) {
            Write-DotfilesLog "ok: Neovim plugin $Plugin"
        }
        else {
            Mark-Missing "Neovim plugin $Plugin"
            $script:NeedNvimPlugins = $true
        }
    }
}

function Test-WezTermStatus {
    if (-not (Test-Command "wezterm")) {
        Mark-Missing "command wezterm"
        $script:NeedPackages = $true
        return
    }

    Write-DotfilesLog "ok: command wezterm"

    $ResizeHelp = & wezterm cli adjust-pane-size --help 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-DotfilesLog "ok: WezTerm pane resize CLI"
    }
    else {
        Mark-Missing "WezTerm pane resize CLI"
    }

    $ShowKeys = & wezterm show-keys --lua 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-DotfilesLog "ok: WezTerm config loads"
    }
    else {
        Mark-Missing "WezTerm config loads"
    }

    $FontOutput = & wezterm ls-fonts 2>$null
    if ($LASTEXITCODE -eq 0 -and $FontOutput -match "Red Hat Mono" -and $FontOutput -match "D2CodingLigature Nerd Font") {
        Write-DotfilesLog "ok: WezTerm font fallback"
    }
    else {
        Mark-Warning "WezTerm did not report both preferred fonts"
    }
}

function Invoke-DoctorCheck {
    $script:Failed = $false
    $script:NeedSync = $false
    $script:NeedFonts = $false
    $script:NeedNvimPlugins = $false
    $script:NeedPackages = $false
    $script:NeedTools = $false
    $script:NeedWindowsConfigSync = $false
    $script:Chezmoi = Resolve-Chezmoi

    Test-CommandStatus -Name "git" -InstallGroup "packages"
    Test-CommandStatus -Name $script:Chezmoi -InstallGroup "packages" -Label "chezmoi"
    Test-CommandStatus -Name "pwsh" -InstallGroup "packages"
    Test-CommandStatus -Name "nvim" -InstallGroup "packages"
    Test-CommandStatus -Name "rustc" -InstallGroup "packages"
    Test-CommandStatus -Name "cargo" -InstallGroup "packages"
    Test-CommandStatus -Name "zoxide" -InstallGroup "tools"
    Test-CommandStatus -Name "direnv" -InstallGroup "tools"

    if (Test-Path -Path $SourceDir -PathType Container) {
        Write-DotfilesLog "ok: chezmoi source $SourceDir"
    }
    else {
        Mark-Missing "chezmoi source $SourceDir"
    }

    Test-FileStatus -Path (Join-Path $HOME ".config\nvim\init.lua") -Description "managed Neovim config"
    Test-FileStatus -Path (Join-Path $HOME ".config\nvim\lua\user\plugins\smart-splits.lua") -Description "Neovim smart-splits config"
    Test-FileStatus -Path (Join-Path $HOME ".config\wezterm\wezterm.lua") -Description "managed WezTerm config"
    Test-FileStatus -Path (Join-Path $HOME ".config\wezterm\user\smart_splits.lua") -Description "WezTerm smart-splits config"
    Test-WindowsConfigFileStatus -Path (Join-Path (Get-LocalAppData) "nvim\init.lua") -Description "Windows Neovim config"
    Test-WindowsConfigFileStatus -Path (Join-Path (Get-LocalAppData) "nvim\lua\user\plugins\smart-splits.lua") -Description "Windows Neovim smart-splits config"

    Test-FontStatus
    Test-NeovimPluginsStatus
    Test-WezTermStatus
}

function Invoke-WindowsPackages {
    $PackageScript = Join-Path (Join-Path $RootDir "packages") "windows.ps1"

    if (-not (Test-Path -Path $PackageScript -PathType Leaf)) {
        Mark-Missing "Windows package script"
        return
    }

    if (-not (Test-Command "winget")) {
        Mark-Missing "command winget"
        return
    }

    Write-DotfilesLog "fix: running Windows package setup"
    & $PackageScript
    Update-ProcessPath
}

function Invoke-ChezmoiSync {
    $script:Chezmoi = Resolve-Chezmoi

    if (-not (Test-Command $script:Chezmoi)) {
        Mark-Warning "skipping chezmoi sync because chezmoi is unavailable"
        return
    }

    Write-DotfilesLog "fix: syncing chezmoi source"
    & $script:Chezmoi --source $SourceDir apply
}

function Invoke-FontInstall {
    $FontScript = Join-Path (Join-Path $RootDir "scripts") "install-fonts.ps1"

    if (Test-Path -Path $FontScript -PathType Leaf) {
        Write-DotfilesLog "fix: installing bundled fonts"
        & $FontScript install
    }
    else {
        Mark-Missing "Windows font install script"
    }
}

function Invoke-UserToolsInstall {
    $ToolsScript = Join-Path (Join-Path $RootDir "scripts") "install-user-tools.ps1"

    if (Test-Path -Path $ToolsScript -PathType Leaf) {
        Write-DotfilesLog "fix: installing Windows user tools"
        & $ToolsScript install
        Update-ProcessPath
    }
    else {
        Mark-Missing "Windows user tools install script"
    }
}

function Invoke-NeovimPluginsInstall {
    $NvimScript = Join-Path (Join-Path $RootDir "scripts") "install-neovim-plugins.ps1"

    if (-not (Test-Command "nvim")) {
        Mark-Warning "skipping Neovim plugin install because nvim is unavailable"
        return
    }

    if (Test-Path -Path $NvimScript -PathType Leaf) {
        Write-DotfilesLog "fix: installing Neovim plugins"
        & $NvimScript install
    }
    else {
        Mark-Missing "Windows Neovim plugin install script"
    }
}

function Invoke-DoctorFix {
    if ($script:NeedPackages) {
        Invoke-WindowsPackages
    }

    if ($script:NeedSync) {
        Invoke-ChezmoiSync
        $script:NeedWindowsConfigSync = $true
    }

    if ($script:NeedWindowsConfigSync) {
        Sync-WindowsConfigPaths
    }

    if ($script:NeedFonts) {
        Invoke-FontInstall
    }

    if ($script:NeedTools) {
        Invoke-UserToolsInstall
    }

    if ($script:NeedNvimPlugins) {
        Invoke-NeovimPluginsInstall
    }
}

Write-DotfilesLog "starting Windows bootstrap"

if (-not (Test-Path -Path $SourceDir -PathType Container)) {
    Write-DotfilesLog "chezmoi source directory is not ready: $SourceDir"
    Write-DotfilesLog "nothing to sync yet"
    exit 0
}

Invoke-DoctorCheck

if (-not $CheckOnly -and $script:Failed) {
    Invoke-DoctorFix
    Invoke-DoctorCheck
}

if ($script:Failed) {
    exit 1
}
