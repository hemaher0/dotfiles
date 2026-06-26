param(
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceDir = if ($env:DOTFILES_SOURCE_DIR) { $env:DOTFILES_SOURCE_DIR } else { Join-Path $RootDir "home" }
$RepoLocalDir = Join-Path (Join-Path $RootDir ".local") "bin"
$RepoChezmoi = Join-Path $RepoLocalDir "chezmoi"
$RepoChezmoiExe = Join-Path $RepoLocalDir "chezmoi.exe"
$Msys2Root = if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { "C:\msys64" }
$Msys2UsrBin = Join-Path $Msys2Root "usr\bin"
$Msys2Pacman = Join-Path $Msys2UsrBin "pacman.exe"
$Msys2Zsh = Join-Path $Msys2UsrBin "zsh.exe"
$Msys2Bash = Join-Path $Msys2UsrBin "bash.exe"

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

function Convert-ChezmoiTargetToPath {
    param(
        [string]$Root,
        [string]$Target
    )

    return Join-Path $Root ($Target -replace "/", "\")
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
        Write-DotfilesLog "fix: backing up stale Windows config: $Path -> $BackupPath"
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

function Add-InstallNeed {
    param(
        [string]$ListName,
        [string]$ComponentId
    )

    if ([string]::IsNullOrWhiteSpace($ComponentId)) {
        return
    }

    $Values = @(Get-Variable -Name $ListName -Scope Script -ValueOnly -ErrorAction SilentlyContinue)
    if ($Values -notcontains $ComponentId) {
        Set-Variable -Name $ListName -Scope Script -Value ($Values + $ComponentId)
    }
}

function Set-InstallNeed {
    param(
        [string]$InstallGroup,
        [string]$ComponentId = ""
    )

    switch ($InstallGroup) {
        "packages" {
            $script:NeedPackages = $true
            Add-InstallNeed -ListName "MissingPackageIds" -ComponentId $ComponentId
        }
        "tools" {
            $script:NeedTools = $true
            Add-InstallNeed -ListName "MissingToolIds" -ComponentId $ComponentId
        }
        "none" { }
    }
}

function Test-CommandStatus {
    param(
        [string]$Name,
        [string]$InstallGroup,
        [string]$ComponentId = "",
        [string]$Label = $Name
    )

    if (Test-Command $Name) {
        Write-DotfilesLog "ok: command $Label"
        return
    }

    Mark-Missing "command $Label"
    Set-InstallNeed -InstallGroup $InstallGroup -ComponentId $ComponentId
}

function Test-Msys2CommandStatus {
    param(
        [string]$Name,
        [string]$InstallGroup,
        [string]$ComponentId = "",
        [string]$Label = $Name
    )

    $CommandPath = Resolve-Msys2Command $Name
    if (-not [string]::IsNullOrWhiteSpace($CommandPath)) {
        Write-DotfilesLog "ok: command $Label"
        return
    }

    Mark-Missing "command $Label"
    Set-InstallNeed -InstallGroup $InstallGroup -ComponentId $ComponentId
}

function Test-ChezmoiStatus {
    $script:Chezmoi = Resolve-Chezmoi

    if (Test-Command $script:Chezmoi) {
        Write-DotfilesLog "ok: command chezmoi"
        return
    }

    Mark-Missing "command chezmoi"
    Set-InstallNeed "packages"
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

function Test-Msys2ZshStatus {
    if (Test-Path -Path $Msys2Pacman -PathType Leaf) {
        Write-DotfilesLog "ok: MSYS2 pacman"
    }
    else {
        Mark-Missing "MSYS2 pacman"
        Set-InstallNeed -InstallGroup "packages" -ComponentId "package-msys2"
        $script:NeedMsys2Zsh = $true
        return
    }

    if (Test-Path -Path $Msys2Zsh -PathType Leaf) {
        $ZshVersion = & $Msys2Zsh --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $ZshVersion) {
            Write-DotfilesLog "ok: MSYS2 $($ZshVersion | Select-Object -First 1)"
        }
        else {
            Write-DotfilesLog "ok: MSYS2 zsh"
        }
    }
    else {
        Mark-Missing "MSYS2 zsh"
        $script:NeedMsys2Zsh = $true
    }
}
function Test-FontStatus {
    $FontDir = Join-Path (Get-LocalAppData) "Microsoft\Windows\Fonts"
    $FontChecks = @(
        @{ Pattern = "RedHatMono-Regular.ttf"; Name = "Red Hat Mono"; ComponentId = "font-red-hat-mono" },
        @{ Pattern = "D2CodingLigatureNerdFont-Regular.ttf"; Name = "D2CodingLigature Nerd Font"; ComponentId = "font-d2coding-ligature" }
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
            Add-InstallNeed -ListName "MissingFontIds" -ComponentId $Font.ComponentId
        }
    }
}

function Test-NeovimPluginsStatus {
    $NvimLazyDir = Join-Path $script:Msys2Home ".local\share\nvim-data\lazy"
    $Plugins = @(
        @{ Dir = "lazy.nvim"; ComponentId = "plugin-nvim-lazy" },
        @{ Dir = "smart-splits.nvim"; ComponentId = "plugin-nvim-smart-splits" },
        @{ Dir = "blink.cmp"; ComponentId = "plugin-nvim-blink-cmp" },
        @{ Dir = "neo-tree.nvim"; ComponentId = "plugin-nvim-neo-tree" },
        @{ Dir = "nvim-treesitter"; ComponentId = "plugin-nvim-treesitter" },
        @{ Dir = "mason.nvim"; ComponentId = "plugin-nvim-mason" }
    )

    foreach ($Plugin in $Plugins) {
        if (Test-Path -Path (Join-Path $NvimLazyDir $Plugin.Dir) -PathType Container) {
            Write-DotfilesLog "ok: Neovim plugin $($Plugin.Dir)"
        }
        else {
            Mark-Missing "Neovim plugin $($Plugin.Dir)"
            $script:NeedNvimPlugins = $true
            Add-InstallNeed -ListName "MissingNvimPluginIds" -ComponentId $Plugin.ComponentId
        }
    }
}

function Test-ZshPluginsStatus {
    $AntidoteDir = Join-Path $script:Msys2Home ".antidote"
    $AntidoteHome = Join-Path $script:Msys2Home ".cache\antidote"

    if (Test-Path -Path (Join-Path $AntidoteDir "antidote.zsh") -PathType Leaf) {
        Write-DotfilesLog "ok: Antidote script"
    }
    else {
        Mark-Missing "Antidote script"
        $script:NeedZshPlugins = $true
    }

    foreach ($Bundle in @(
            "github.com\romkatv\powerlevel10k",
            "github.com\wfxr\forgit",
            "github.com\jeffreytse\zsh-vi-mode"
        )) {
        if (Test-Path -Path (Join-Path $AntidoteHome $Bundle) -PathType Container) {
            Write-DotfilesLog "ok: zsh bundle $Bundle"
        }
        else {
            Mark-Missing "zsh bundle $Bundle"
            $script:NeedZshPlugins = $true
        }
    }
}

function Test-WezTermStatus {
    if (-not (Test-Command "wezterm")) {
        Mark-Missing "command wezterm"
        Set-InstallNeed -InstallGroup "packages" -ComponentId "package-wezterm"
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
    Update-ProcessPath

    $script:Failed = $false
    $script:NeedSync = $false
    $script:NeedFonts = $false
    $script:NeedNvimPlugins = $false
    $script:NeedZshPlugins = $false
    $script:NeedPackages = $false
    $script:NeedTools = $false
    $script:NeedMsys2Zsh = $false
    $script:MissingPackageIds = @()
    $script:MissingToolIds = @()
    $script:MissingFontIds = @()
    $script:MissingNvimPluginIds = @()
    $script:Chezmoi = Resolve-Chezmoi
    $script:Msys2Home = Get-Msys2HomePath

    Test-CommandStatus -Name "git" -InstallGroup "packages" -ComponentId "package-git"
    Test-Msys2CommandStatus -Name "bash" -InstallGroup "packages" -ComponentId "package-msys2" -Label "MSYS2 bash"
    Test-Msys2ZshStatus
    Test-CommandStatus -Name $script:Chezmoi -InstallGroup "packages" -ComponentId "package-chezmoi" -Label "chezmoi"
    Test-CommandStatus -Name "pwsh" -InstallGroup "packages" -ComponentId "package-pwsh"
    Test-Msys2CommandStatus -Name "nvim" -InstallGroup "packages" -ComponentId "package-msys2" -Label "MSYS2 nvim"
    Test-CommandStatus -Name "rustc" -InstallGroup "packages" -ComponentId "dependency-rust"
    Test-CommandStatus -Name "cargo" -InstallGroup "packages" -ComponentId "dependency-rust"
    Test-Msys2CommandStatus -Name "zoxide" -InstallGroup "tools" -ComponentId "tool-zoxide"
    Test-Msys2CommandStatus -Name "direnv" -InstallGroup "tools" -ComponentId "tool-direnv"

    if (Test-Path -Path $SourceDir -PathType Container) {
        Write-DotfilesLog "ok: chezmoi source $SourceDir"
    }
    else {
        Mark-Missing "chezmoi source $SourceDir"
    }

    Test-FileStatus -Path (Join-Path $script:Msys2Home ".config\nvim\init.lua") -Description "MSYS2 Neovim config"
    Test-FileStatus -Path (Join-Path $script:Msys2Home ".config\nvim\lua\user\plugins\smart-splits.lua") -Description "MSYS2 Neovim smart-splits config"
    Test-FileStatus -Path (Join-Path $script:Msys2Home ".config\nvim-lite\init.lua") -Description "MSYS2 Neovim lite config"
    Test-FileStatus -Path (Join-Path $script:Msys2Home ".config\tmux\tmux.conf") -Description "MSYS2 tmux config"
    Test-FileStatus -Path (Join-Path $script:Msys2Home ".zshenv") -Description "MSYS2 zshenv"
    Test-FileStatus -Path (Join-Path $script:Msys2Home ".zshrc") -Description "MSYS2 zshrc"
    Test-FileStatus -Path (Join-Path $script:Msys2Home ".p10k.zsh") -Description "MSYS2 Powerlevel10k config"
    Test-FileStatus -Path (Join-Path $script:Msys2Home ".config\zsh\plugins.txt") -Description "MSYS2 zsh plugin manifest"
    Test-FileStatus -Path (Join-Path $HOME ".config\wezterm\wezterm.lua") -Description "Windows WezTerm config"
    Test-FileStatus -Path (Join-Path $HOME ".config\wezterm\user\smart_splits.lua") -Description "Windows WezTerm smart-splits config"

    Test-FontStatus
    Test-ZshPluginsStatus
    Test-NeovimPluginsStatus
    Test-WezTermStatus
}

function Invoke-WindowsPackages {
    param([string]$PackageId = "")

    $PackageScript = Join-Path (Join-Path $RootDir "packages") "windows.ps1"

    if (-not (Test-Path -Path $PackageScript -PathType Leaf)) {
        Mark-Missing "Windows package script"
        return
    }

    if (-not (Test-Command "winget")) {
        Mark-Missing "command winget"
        return
    }

    $PackageIds = if ([string]::IsNullOrWhiteSpace($PackageId)) { @($script:MissingPackageIds) } else { @($PackageId) }
    if ($PackageIds.Count -eq 0) {
        Write-DotfilesLog "fix: running Windows package setup"
        & $PackageScript
    }
    else {
        foreach ($PackageId in $PackageIds) {
            Write-DotfilesLog "fix: installing Windows package $PackageId"
            & $PackageScript install $PackageId
        }
    }
    Update-ProcessPath
}

function Ensure-ChezmoiAvailable {
    Update-ProcessPath
    $script:Chezmoi = Resolve-Chezmoi

    if (Test-Command $script:Chezmoi) {
        return $true
    }

    Write-DotfilesLog "fix: installing chezmoi"
    Invoke-WindowsPackages -PackageId "package-chezmoi"
    Update-ProcessPath
    $script:Chezmoi = Resolve-Chezmoi

    if (Test-Command $script:Chezmoi) {
        return $true
    }

    Mark-Missing "command chezmoi after package install"
    return $false
}

function Invoke-ChezmoiSync {
    if (-not (Ensure-ChezmoiAvailable)) {
        Mark-Warning "skipping chezmoi sync because chezmoi is unavailable after install"
        return
    }

    Backup-StaleWindowsConfigPaths

    $WindowsTargets = @(Get-WindowsChezmoiTargets | ForEach-Object { Convert-ChezmoiTargetToPath -Root $HOME -Target $_ })
    Write-DotfilesLog "fix: syncing Windows-native chezmoi targets to Windows home"
    & $script:Chezmoi --source $SourceDir apply --force @WindowsTargets
    if ($LASTEXITCODE -ne 0) {
        Mark-Warning "chezmoi Windows sync failed with exit code $LASTEXITCODE"
        return
    }

    $Msys2Home = Get-Msys2HomePath
    New-Item -ItemType Directory -Path $Msys2Home -Force | Out-Null
    $Msys2Targets = @(Get-Msys2ChezmoiTargets | ForEach-Object { Convert-ChezmoiTargetToPath -Root $Msys2Home -Target $_ })
    Write-DotfilesLog "fix: syncing MSYS2 chezmoi targets to MSYS2 home $Msys2Home"
    & $script:Chezmoi --source $SourceDir --destination $Msys2Home apply --force @Msys2Targets
    if ($LASTEXITCODE -ne 0) {
        Mark-Warning "chezmoi MSYS2 sync failed with exit code $LASTEXITCODE"
    }
}

function Invoke-FontInstall {
    $FontScript = Join-Path (Join-Path $RootDir "scripts") "install-fonts.ps1"

    if (Test-Path -Path $FontScript -PathType Leaf) {
        $FontIds = @($script:MissingFontIds)
        if ($FontIds.Count -eq 0) {
            $FontIds = @("all")
        }

        foreach ($FontId in $FontIds) {
            Write-DotfilesLog "fix: installing bundled font $FontId"
            & $FontScript install $FontId
        }
    }
    else {
        Mark-Missing "Windows font install script"
    }
}

function Invoke-UserToolsInstall {
    $ToolsScript = Join-Path (Join-Path $RootDir "scripts") "install-user-tools.ps1"

    if (Test-Path -Path $ToolsScript -PathType Leaf) {
        $ToolIds = @($script:MissingToolIds)
        if ($ToolIds.Count -eq 0) {
            $ToolIds = @("all")
        }

        foreach ($ToolId in $ToolIds) {
            Write-DotfilesLog "fix: installing Windows user tool $ToolId"
            & $ToolsScript install $ToolId
        }
        Update-ProcessPath
    }
    else {
        Mark-Missing "Windows user tools install script"
    }
}

function Invoke-NeovimPluginsInstall {
    if (-not (Test-Msys2Command "nvim")) {
        Mark-Warning "skipping Neovim plugin install because MSYS2 nvim is unavailable"
        return
    }

    $NvimScript = Join-Path (Join-Path $RootDir "scripts") "install-neovim-plugins.sh"
    if (Test-Path -Path $NvimScript -PathType Leaf) {
        $PluginIds = @($script:MissingNvimPluginIds)
        if ($PluginIds.Count -eq 0) {
            $PluginIds = @("all")
        }

        foreach ($PluginId in $PluginIds) {
            Write-DotfilesLog "fix: installing MSYS2 Neovim plugin $PluginId"
            Invoke-Msys2RepoScript "scripts/install-neovim-plugins.sh" @("install", $PluginId)
        }
    }
    else {
        Mark-Missing "MSYS2 Neovim plugin install script"
    }
}

function Invoke-ZshPluginsInstall {
    if (-not (Test-Msys2Command "zsh")) {
        Mark-Warning "skipping zsh plugin install because MSYS2 zsh is unavailable"
        return
    }

    $ZshScript = Join-Path (Join-Path $RootDir "scripts") "install-antidote.sh"
    if (Test-Path -Path $ZshScript -PathType Leaf) {
        Write-DotfilesLog "fix: installing MSYS2 zsh plugins"
        Invoke-Msys2RepoScript "scripts/install-antidote.sh" @("install")
        Invoke-Msys2RepoScript "scripts/install-antidote.sh" @("update")
    }
    else {
        Mark-Missing "MSYS2 zsh plugin install script"
    }
}

function Invoke-Msys2ZshInstall {
    $ZshScript = Join-Path (Join-Path $RootDir "scripts") "install-msys2-zsh.ps1"

    if (Test-Path -Path $ZshScript -PathType Leaf) {
        Write-DotfilesLog "fix: installing MSYS2 zsh"
        & $ZshScript install
    }
    else {
        Mark-Missing "MSYS2 zsh install script"
    }
}

function Invoke-DoctorFix {
    if ($script:NeedPackages) {
        Invoke-WindowsPackages
    }

    if ($script:NeedSync) {
        Invoke-ChezmoiSync
    }

    if ($script:NeedMsys2Zsh) {
        Invoke-Msys2ZshInstall
    }

    if ($script:NeedFonts) {
        Invoke-FontInstall
    }

    if ($script:NeedTools) {
        Invoke-UserToolsInstall
    }

    if ($script:NeedZshPlugins) {
        Invoke-ZshPluginsInstall
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
