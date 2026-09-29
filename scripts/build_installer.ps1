param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$versionLine = Select-String -Path (Join-Path $projectRoot 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$' | Select-Object -First 1
if (-not $versionLine) { throw 'pubspec.yaml does not contain a version.' }
$version = $versionLine.Matches[0].Groups[1].Value
$buildNumber = $versionLine.Matches[0].Groups[2].Value
$fullVersion = "$version+$buildNumber"
$packageName = "Fly-Setup-$version-build$buildNumber"

& (Join-Path $PSScriptRoot 'build_windows_release.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }

$releaseExe = Join-Path $projectRoot 'build\windows\x64\runner\Release\fly.exe'
if (-not (Test-Path -LiteralPath $releaseExe)) { throw 'Release fly.exe is missing.' }
$builtVersion = (Get-Content -LiteralPath (Join-Path (Split-Path -Parent $releaseExe) 'fly-release-version.txt') -Raw).Trim()
if ($builtVersion -ne $fullVersion) { throw 'Release executable version does not match pubspec.yaml.' }

$secretPatterns = 'AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY'
$scanRoots = @('lib', 'windows', 'installer', 'scripts') | ForEach-Object { Join-Path $projectRoot $_ }
$matches = & rg -l -I -e $secretPatterns @scanRoots 2>$null
if ($LASTEXITCODE -eq 0 -and $matches) { throw 'Potential secret found in release sources. Review matching file paths locally.' }
if ($LASTEXITCODE -gt 1) { throw 'Secret scan failed.' }

$isccCandidates = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'),
  (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
  (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe'),
  (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
  (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
)
$iscc = $isccCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $iscc) { throw 'ISCC.exe not found. Install official Inno Setup first.' }

$dist = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$script = Join-Path $projectRoot 'installer\Fly.iss'
& $iscc "/DAppVersion=$version" "/DPackageName=$packageName" $script
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }

$installer = Join-Path $dist "$packageName.exe"
if (-not (Test-Path -LiteralPath $installer)) { throw 'Installer output is missing.' }
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash
$hashFile = Join-Path $dist "$packageName.sha256.txt"
Set-Content -LiteralPath $hashFile -Encoding ascii -Value "$hash  $packageName.exe"

$testing = @"
Fly $fullVersion Windows x64 test package

1. Run $packageName.exe.
2. The default per-user install folder is %LOCALAPPDATA%\Programs\Fly.
3. Keep the desktop shortcut selected, then launch Fly after setup.
4. On first run choose a data folder; Documents\FlyData is recommended.
5. The uninstaller removes the application but deliberately keeps FlyData and settings.

SHA256
$hash

This build uses Dart identifier obfuscation. Private split-debug symbols are retained by the developer and are not included here. Obfuscation increases reverse-engineering difficulty but is not absolute source protection.

This installer is unsigned unless an Authenticode certificate is configured. Windows SmartScreen may show Unknown Publisher during testing. Do not label it a signed commercial release without publisher verification.
"@
Set-Content -LiteralPath (Join-Path $dist 'README-TESTING.txt') -Encoding utf8 -Value $testing

Write-Host "Installer: $installer"
Write-Host "SHA256: $hash"
