param([string]$PackagePath = '')

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repo 'scripts/build_license_issuer.ps1') -PackagePath $PackagePath
$fixtureDir = Join-Path $repo '.buildlog/license-issuer-tests'
New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
$fixtureOutput = Join-Path $fixtureDir 'compatibility.json'
$testExe = Join-Path $build 'IssuerHarness.exe'
$testArguments = @($arguments | Where-Object {
    $_ -notlike '/target:*' -and $_ -notlike '/out:*' -and $_ -ne (Join-Path $source 'Program.cs')
})
$testArguments = @('/target:exe', ('/out:' + $testExe), '/reference:System.Web.Extensions.dll') + $testArguments + @((Join-Path $PSScriptRoot 'IssuerHarness.cs'))
& $compiler @testArguments
if ($LASTEXITCODE -ne 0) { throw 'Native issuer test build failed.' }
& $testExe $fixtureOutput
if ($LASTEXITCODE -ne 0) { throw 'Native issuer tests failed.' }
Write-Host ('Ephemeral-key fixture: ' + $fixtureOutput)
