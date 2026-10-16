param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$signingRoot = Join-Path $projectRoot 'license_tools/private/android'
foreach ($name in @('signing.properties', 'fly-android-release.p12', 'identity.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $signingRoot $name))) {
        throw 'Restore the original private Android release signing directory before building. This script never generates replacement keys.'
    }
}
$bookDefines = Join-Path $projectRoot 'license_tools/private/book_build_defines.json'
if (-not (Test-Path -LiteralPath $bookDefines)) { throw 'Restore the original book reader configuration before building.' }
$versionLine = Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$' | Select-Object -First 1
if (-not $versionLine) { throw 'Application version is missing.' }
$version = $versionLine.Matches[0].Groups[1].Value
$buildNumber = $versionLine.Matches[0].Groups[2].Value
$flutter = (Get-Command flutter.bat -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = 'D:/ProgramData/flutter/bin/flutter.bat' }
if (-not (Test-Path -LiteralPath $flutter)) { throw 'Flutter SDK was not found.' }
$licensePublicKey = (Get-Content -LiteralPath (Join-Path $projectRoot 'license_tools/public_key.txt') -Raw).Trim()
$symbols = Join-Path $projectRoot "private_symbols/$version+$buildNumber/android-release"
Push-Location $projectRoot
try {
    & $flutter build apk --release "--build-name=$version" "--build-number=$buildNumber" `
        "--dart-define=FLY_APP_VERSION=$version+$buildNumber" `
        '--dart-define=ENABLE_LOCAL_LICENSE=false' `
        "--dart-define=LOCAL_LICENSE_PUBLIC_KEY=$licensePublicKey" `
        '--dart-define=ENABLE_KNOWLEDGE_HUB=true' "--dart-define-from-file=$bookDefines" `
        --obfuscate "--split-debug-info=$symbols"
    if ($LASTEXITCODE -ne 0) { throw 'Android release build failed.' }
    Write-Host 'Android release APK built with the original Fly signing identity.'
    Write-Host 'Verify the APK certificate against android/release-certificate.sha256 before distribution.'
} finally {
    Pop-Location
}
