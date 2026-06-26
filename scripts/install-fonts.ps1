param(
    [ValidateSet("install", "update", "help")]
    [string]$Command = "install",
    [string]$FontId = "all"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

function Write-DotfilesLog {
    param([string]$Message)
    Write-Host "dotfiles: $Message"
}

function Show-Usage {
    @"
Usage: install-fonts.ps1 [install|update|help] [all|font-red-hat-mono|font-d2coding-ligature]

Installs the bundled terminal fonts for the current Windows user:
  - Red Hat Mono
  - D2CodingLigature Nerd Font
"@
}

function Get-EnvOrDefault {
    param(
        [string]$Name,
        [string]$Default
    )

    $Value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    return $Value
}

function Install-FontFile {
    param(
        [System.IO.FileInfo]$FontFile,
        [string]$FontDir,
        [string]$RegistryPath
    )

    $TargetPath = Join-Path $FontDir $FontFile.Name

    try {
        Copy-Item -Path $FontFile.FullName -Destination $TargetPath -Force
    }
    catch {
        if (Test-Path -Path $TargetPath -PathType Leaf) {
            Write-DotfilesLog "font is already present and could not be replaced: $($FontFile.Name)"
        }
        else {
            throw
        }
    }

    $FontType = if ($FontFile.Extension -ieq ".otf") { "OpenType" } else { "TrueType" }
    $RegistryName = "$($FontFile.BaseName) ($FontType)"
    New-ItemProperty -Path $RegistryPath -Name $RegistryName -Value $TargetPath -PropertyType String -Force | Out-Null
}

function Install-FontFiles {
    param(
        [string]$SourceDir,
        [string]$FontDir,
        [string]$RegistryPath
    )

    if (-not (Test-Path -Path $SourceDir -PathType Container)) {
        Write-DotfilesLog "font source directory is not ready: $SourceDir"
        exit 1
    }

    $FontFiles = Get-ChildItem -Path $SourceDir -Recurse -File |
        Where-Object { $_.Extension -ieq ".ttf" -or $_.Extension -ieq ".otf" }

    if ($FontFiles.Count -eq 0) {
        Write-DotfilesLog "no font files found in $SourceDir"
        exit 1
    }

    foreach ($FontFile in $FontFiles) {
        Install-FontFile -FontFile $FontFile -FontDir $FontDir -RegistryPath $RegistryPath
    }

    Write-DotfilesLog "installed $($FontFiles.Count) bundled font files"
}

function Select-FontSources {
    param(
        [string]$SourceRoot,
        [string]$Id
    )

    $Fonts = @(
        @{ ComponentId = "font-red-hat-mono"; Id = "red-hat-mono"; Name = "Red Hat Mono"; Directory = "RedHatMono" },
        @{ ComponentId = "font-d2coding-ligature"; Id = "d2coding-ligature"; Name = "D2CodingLigature Nerd Font"; Directory = "D2Coding" }
    )

    if ([string]::IsNullOrWhiteSpace($Id) -or $Id -eq "all") {
        return $Fonts
    }

    $Selected = @($Fonts | Where-Object { $_.ComponentId -eq $Id -or $_.Id -eq $Id -or $_.Name -eq $Id })
    if ($Selected.Count -eq 0) {
        Write-DotfilesLog "unknown Windows font id: $Id"
        exit 1
    }

    return $Selected
}

if ($Command -eq "help") {
    Show-Usage
    exit 0
}

$DefaultFontSourceDir = Join-Path (Join-Path $RootDir "assets") "fonts"
$FontSourceDir = Get-EnvOrDefault -Name "FONT_SOURCE_DIR" -Default $DefaultFontSourceDir
$FontDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
$RegistryPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"

New-Item -ItemType Directory -Path $FontDir -Force | Out-Null
New-Item -Path $RegistryPath -Force | Out-Null

foreach ($Font in (Select-FontSources -SourceRoot $FontSourceDir -Id $FontId)) {
    Write-DotfilesLog "installing font family $($Font.Name)"
    Install-FontFiles -SourceDir (Join-Path $FontSourceDir $Font.Directory) -FontDir $FontDir -RegistryPath $RegistryPath
}

Write-DotfilesLog "installed fonts into $FontDir"
Write-DotfilesLog "restart terminal applications if the new fonts do not appear"
