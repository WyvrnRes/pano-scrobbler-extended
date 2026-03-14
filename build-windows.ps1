[CmdletBinding()]
param(
    [ValidateSet('Compile', 'Distributable', 'Inno', 'Nsis', 'All', 'Run')]
    [string]$Target = 'Distributable',

    [string]$NativeResourcesPath,
    [switch]$NoDaemon,
    [switch]$SkipExportLibraryDefinitions,
    [switch]$SkipPreflight
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$gradleWrapper = Join-Path $repoRoot 'gradlew.bat'
$composeAppDir = Join-Path $repoRoot 'composeApp'
$windowsResourcesDir = Join-Path $composeAppDir 'resources\windows-x64'
$syncScript = Join-Path $repoRoot 'sync-windows-native-resources.ps1'
$localProperties = Join-Path $repoRoot 'local.properties'
$innoExe = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
$nsisExe = Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe'
$commonGradleArgs = @('-PaboutLibraries.exportVariant=desktop')

if ($NoDaemon) {
    $commonGradleArgs += '--no-daemon'
}

function Assert-FileExists([string]$Path, [string]$Message) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw $Message
    }
}

function Assert-DirectoryExists([string]$Path, [string]$Message) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw $Message
    }
}

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-NativeResourceDirectory([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }

    $requiredFiles = @(
        'pano_native_components.dll',
        'native_webview.dll'
    )

    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $requiredFile) -PathType Leaf)) {
            return $false
        }
    }

    return $true
}

function Get-NativeResourceCandidates {
    $repoParent = Split-Path -Parent $repoRoot
    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @(
        $NativeResourcesPath,
        $windowsResourcesDir,
        (Join-Path $repoRoot 'libs-windows-x64'),
        (Join-Path $repoRoot 'artifacts\libs-windows-x64'),
        (Join-Path $repoRoot '.artifacts\libs-windows-x64'),
        (Join-Path $repoRoot 'build\libs-windows-x64'),
        (Join-Path $repoRoot 'tmp\libs-windows-x64'),
        (Join-Path $repoParent 'pano-native-components\build\windows-x64'),
        (Join-Path $repoParent 'pano-native-components\dist\windows-x64'),
        (Join-Path $repoParent 'pano-native-components\artifacts\windows-x64'),
        (Join-Path $repoParent 'pano-native-components\artifacts\libs-windows-x64'),
        (Join-Path $repoParent 'pano-native-components\build\libs-windows-x64')
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $candidates.Contains($candidate)) {
            $null = $candidates.Add($candidate)
        }
    }

    return $candidates
}

function Ensure-NativeResourcesReady {
    if (Test-NativeResourceDirectory $windowsResourcesDir) {
        Write-Step "Using native resources from $windowsResourcesDir"
        return
    }

    foreach ($candidate in Get-NativeResourceCandidates) {
        if ($candidate -eq $windowsResourcesDir) {
            continue
        }

        if (Test-NativeResourceDirectory $candidate) {
            Assert-FileExists $syncScript 'sync-windows-native-resources.ps1 was not found.'
            Write-Step "Syncing native resources from $candidate"
            Push-Location $repoRoot
            try {
                & $syncScript -Source $candidate -Force
            }
            finally {
                Pop-Location
            }

            if (Test-NativeResourceDirectory $windowsResourcesDir) {
                return
            }
        }
    }

    throw @"
Packaging for Windows expects native resources at:
$windowsResourcesDir

No usable source directory was auto-detected.
Run:
powershell -ExecutionPolicy Bypass -File .\sync-windows-native-resources.ps1 -Source <path-to-windows-native-resources>

The source directory must contain at least:
- pano_native_components.dll
- native_webview.dll
"@
}

function Invoke-Gradle([string[]]$Tasks) {
    $args = @($Tasks) + $commonGradleArgs
    Write-Step (("Running Gradle: {0}" -f ($args -join ' ')))
    Push-Location $repoRoot
    try {
        & $gradleWrapper @args
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle exited with code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-Preflight {
    Assert-FileExists $gradleWrapper 'Run this script from the repository root. `gradlew.bat` was not found.'

    if (-not (Test-Path -LiteralPath $localProperties -PathType Leaf)) {
        Write-Warning 'local.properties was not found. Desktop compile may still work, but configured API keys are normally expected for full builds.'
    }

    switch ($Target) {
        'Compile' { return }
        'Run' { return }
        default {
            Ensure-NativeResourcesReady
        }
    }

    if ($Target -in @('Inno', 'All') -and -not (Test-Path -LiteralPath $innoExe -PathType Leaf)) {
        throw "Inno Setup 6 was not found at '$innoExe'. Install Inno Setup or use -Target Distributable."
    }

    if ($Target -eq 'Nsis' -and -not (Test-Path -LiteralPath $nsisExe -PathType Leaf)) {
        throw "NSIS was not found at '$nsisExe'. Install NSIS or use -Target Distributable."
    }
}

if (-not $SkipPreflight) {
    Invoke-Preflight
}

switch ($Target) {
    'Compile' {
        Invoke-Gradle @(':composeApp:compileKotlinDesktop')
    }

    'Run' {
        Invoke-Gradle @(':composeApp:run')
    }

    'Distributable' {
        $tasks = @()
        if (-not $SkipExportLibraryDefinitions) {
            $tasks += ':composeApp:exportLibraryDefinitionsDesktop'
        }
        $tasks += ':composeApp:createReleaseDistributable'
        Invoke-Gradle $tasks
    }

    'Inno' {
        $tasks = @()
        if (-not $SkipExportLibraryDefinitions) {
            $tasks += ':composeApp:exportLibraryDefinitionsDesktop'
        }
        $tasks += ':composeApp:createReleaseDistributable'
        $tasks += ':composeApp:packageInno'
        Invoke-Gradle $tasks
    }

    'Nsis' {
        $tasks = @()
        if (-not $SkipExportLibraryDefinitions) {
            $tasks += ':composeApp:exportLibraryDefinitionsDesktop'
        }
        $tasks += ':composeApp:createReleaseDistributable'
        $tasks += ':composeApp:packageWindowsNsis'
        Invoke-Gradle $tasks
    }

    'All' {
        $tasks = @()
        if (-not $SkipExportLibraryDefinitions) {
            $tasks += ':composeApp:exportLibraryDefinitionsDesktop'
        }
        $tasks += ':composeApp:createReleaseDistributable'
        $tasks += ':composeApp:packageInno'
        if (Test-Path -LiteralPath $nsisExe -PathType Leaf) {
            $tasks += ':composeApp:packageWindowsNsis'
        }
        else {
            Write-Warning 'NSIS not found; skipping packageWindowsNsis in All mode.'
        }
        Invoke-Gradle $tasks
    }
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
switch ($Target) {
    'Compile' { Write-Host 'Desktop Kotlin sources compiled successfully.' -ForegroundColor Green }
    'Run' { Write-Host 'The desktop run task completed.' -ForegroundColor Green }
    'Distributable' { Write-Host 'Look under composeApp\build\compose\ for the Windows distributable output.' -ForegroundColor Green }
    'Inno' { Write-Host 'Installer output should be under dist\.' -ForegroundColor Green }
    'Nsis' { Write-Host 'Installer output should be under dist\.' -ForegroundColor Green }
    'All' { Write-Host 'Windows packaging tasks completed. Check dist\ for installers.' -ForegroundColor Green }
}



