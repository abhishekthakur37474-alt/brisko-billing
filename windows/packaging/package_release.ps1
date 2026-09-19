<#
.SYNOPSIS
    Packages the Brisko Billing Windows release into a client-ready folder and zip.

.DESCRIPTION
    Flutter's Windows deployment is NOT a single .exe. The runnable application is the
    whole contents of build\windows\x64\runner\Release\ - the executable, the Flutter
    engine DLL, the ICU data file, the plugin DLLs and the data\ directory (which holds
    flutter_assets, including the Brisko receipt logo). Shipping only brisko_billing.exe
    produces an application that will not start on the client's machine.

    This script must be run on a Windows host, AFTER:
        flutter pub get
        flutter build windows --release
    (optionally with the cloud --dart-define values; see CLIENT_SETUP.md).

    It copies the complete release output into
        dist\Brisko-Billing-Windows-x64-Release\
    and produces
        dist\Brisko-Billing-Windows-x64-Release.zip
    which is the artifact to hand to the client. The client unzips it anywhere and runs
    brisko_billing.exe - no developer tools required on their machine.

.NOTES
    This performs no build and modifies nothing under build\; it only copies the release
    output that flutter build windows --release already produced.
#>

[CmdletBinding()]
param(
    # Repository root. Defaults to two levels up from this script (windows\packaging\).
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'

$releaseDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
$exePath    = Join-Path $releaseDir 'brisko_billing.exe'

if (-not (Test-Path $exePath)) {
    Write-Error @"
Release build not found at:
    $exePath

Build it first on this Windows machine:
    flutter pub get
    flutter build windows --release

Then run this script again.
"@
    exit 1
}

$distDir    = Join-Path $ProjectRoot 'dist'
$packageDir = Join-Path $distDir 'Brisko-Billing-Windows-x64-Release'
$zipPath    = Join-Path $distDir 'Brisko-Billing-Windows-x64-Release.zip'

# Start from a clean package folder so no stale files from a previous build survive.
if (Test-Path $packageDir) { Remove-Item -Recurse -Force $packageDir }
if (Test-Path $zipPath)    { Remove-Item -Force $zipPath }
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

# Copy the ENTIRE release directory (exe + all DLLs + data\). This is the whole
# deployable application.
Copy-Item -Path (Join-Path $releaseDir '*') -Destination $packageDir -Recurse -Force

# Sanity check: the pieces a Flutter Windows app cannot start without.
$required = @('brisko_billing.exe', 'flutter_windows.dll', 'data')
foreach ($item in $required) {
    if (-not (Test-Path (Join-Path $packageDir $item))) {
        Write-Error "Package is incomplete: '$item' is missing from the release output."
        exit 1
    }
}

Compress-Archive -Path (Join-Path $packageDir '*') -DestinationPath $zipPath -Force

Write-Host ''
Write-Host 'Packaged Brisko Billing (Windows x64, Release):' -ForegroundColor Green
Write-Host "  Folder: $packageDir"
Write-Host "  Zip:    $zipPath"
Write-Host ''
Write-Host 'Hand the zip to the client. They unzip it and run brisko_billing.exe.'
