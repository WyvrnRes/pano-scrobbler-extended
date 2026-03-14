[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Source,
    [string]$Destination = (Join-Path $PSScriptRoot 'composeApp\resources\windows-x64'),
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$requiredFiles = @(
    'pano_native_components.dll',
    'native_webview.dll'
)

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

    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $requiredFile) -PathType Leaf)) {
            return $false
        }
    }

    return $true
}

function Resolve-SourceDirectory {
    if ($Source) {
        if (Test-NativeResourceDirectory $Source) {
            return (Resolve-Path -LiteralPath $Source).Path
        }
        throw "The supplied source directory is missing required files: $Source"
    }

    $repoRoot = $PSScriptRoot
    $repoParent = Split-Path -Parent $repoRoot
    $candidates = @(
        (Join-Path $repoRoot 'libs-windows-x64'),
        (Join-Path $repoRoot 'artifacts\libs-windows-x64'),
        (Join-Path $repoRoot '.artifacts\libs-windows-x64'),
        (Join-Path $repoRoot 'build\libs-windows-x64'),
        (Join-Path $repoRoot 'tmp\libs-windows-x64'),
        (Join-Path $repoParent 'pano-native-components\build\windows-x64'),
        (Join-Path $repoParent 'pano-native-components\build\libs-windows-x64'),
        (Join-Path $repoParent 'pano-native-components\dist\windows-x64'),
        (Join-Path $repoParent 'pano-native-components\artifacts\windows-x64'),
        (Join-Path $repoParent 'pano-native-components\artifacts\libs-windows-x64')
    )

    foreach ($candidate in $candidates) {
        if (Test-NativeResourceDirectory $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw @"
No Windows native resource source was found automatically.

Pass -Source with a directory containing:
- pano_native_components.dll
- native_webview.dll

Example:
powershell -ExecutionPolicy Bypass -File .\sync-windows-native-resources.ps1 -Source C:\path\to\windows-x64
"@
}

$resolvedSource = Resolve-SourceDirectory
$resolvedDestinationParent = Split-Path -Parent $Destination
if (-not (Test-Path -LiteralPath $resolvedDestinationParent -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedDestinationParent -Force | Out-Null
}

$destinationPath = $Destination
if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
    throw "Destination exists as a file: $destinationPath"
}

if ((Test-Path -LiteralPath $destinationPath -PathType Container) -and -not $Force) {
    $existingFiles = Get-ChildItem -LiteralPath $destinationPath -Force | Select-Object -First 1
    if ($existingFiles) {
        throw "Destination already contains files. Re-run with -Force to replace: $destinationPath"
    }
}

if ($PSCmdlet.ShouldProcess($destinationPath, "Sync Windows native resources from $resolvedSource")) {
    Write-Step "Source: $resolvedSource"
    Write-Step "Destination: $destinationPath"

    if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
    }

    if ($Force) {
        Get-ChildItem -LiteralPath $destinationPath -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force
    }

    Copy-Item -Path (Join-Path $resolvedSource '*') -Destination $destinationPath -Recurse -Force

    if (-not (Test-NativeResourceDirectory $destinationPath)) {
        throw "Sync completed, but destination is still missing required files: $destinationPath"
    }

    Write-Host ''
    Write-Host 'Done.' -ForegroundColor Green
    Write-Host "Windows native resources are ready at $destinationPath" -ForegroundColor Green
}

