param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$versionLine = Select-String -Path $pubspecPath -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$' | Select-Object -First 1
if (-not $versionLine) { throw 'pubspec.yaml must contain a semantic version and build number.' }
$version = $versionLine.Matches[0].Groups[1].Value
$buildNumber = $versionLine.Matches[0].Groups[2].Value
$fullVersion = "$version+$buildNumber"

$publicKeyPath = Join-Path $projectRoot 'license_tools\public_key.txt'
if (-not (Test-Path -LiteralPath $publicKeyPath)) { throw 'Release licensing public key is missing.' }
$publicKey = (Get-Content -LiteralPath $publicKeyPath -Raw).Trim()
if ($publicKey -notmatch '^[A-Za-z0-9_-]{43}$') { throw 'Release licensing public key is invalid.' }

$flutter = (Get-Command flutter.bat -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = 'D:\ProgramData\flutter\bin\flutter.bat' }
if (-not (Test-Path -LiteralPath $flutter)) { throw "Flutter SDK not found: $flutter" }

$symbols = Join-Path $projectRoot (Join-Path 'private_symbols' $version)
New-Item -ItemType Directory -Force -Path $symbols | Out-Null

Push-Location $projectRoot
try {
  & $flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
  & $flutter analyze --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed.' }
  & $flutter test --no-pub --concurrency=1
  if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }
  & $flutter build windows --release "--build-name=$version" "--build-number=$buildNumber" `
    "--dart-define=FLY_APP_VERSION=$fullVersion" `
    '--dart-define=ENABLE_LOCAL_LICENSE=true' `
    "--dart-define=LOCAL_LICENSE_PUBLIC_KEY=$publicKey" `
    --obfuscate "--split-debug-info=$symbols"
  if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows release build failed.' }

  $release = Join-Path $projectRoot 'build\windows\x64\runner\Release'
  foreach ($required in @('fly.exe', 'flutter_windows.dll', 'data')) {
    if (-not (Test-Path -LiteralPath (Join-Path $release $required))) {
      throw "Release output is incomplete: $required"
    }
  }
  Set-Content -LiteralPath (Join-Path $release 'fly-release-version.txt') -Encoding ascii -Value $fullVersion
  Write-Host "Fly $fullVersion Windows release is ready."
  Write-Host "Private symbols: $symbols"
} finally {
  Pop-Location
}
