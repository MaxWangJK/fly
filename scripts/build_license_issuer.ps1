param([string]$PackagePath = '')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot 'license_tools/portable_issuer'
$build = Join-Path $projectRoot 'license_tools/private/portable-build'
$delivery = Join-Path $projectRoot 'license_tools/private/portable'
$identity = Join-Path $projectRoot 'license_tools/private/issuer.pem'
$public = Join-Path $projectRoot 'license_tools/public_key.txt'
$python = Join-Path $projectRoot 'license_tools/private/runtime/Scripts/python.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
foreach ($required in @($identity, $public, $python, $compiler)) {
    if (-not (Test-Path -LiteralPath $required)) { throw 'Restore the original internal issuer files and Windows build environment. No new signing identity will be created.' }
}
$spec = Get-Content -LiteralPath (Join-Path $source 'dependency.json') -Raw | ConvertFrom-Json
if (-not $PackagePath) {
    $cache = Join-Path $projectRoot '.buildlog/license-issuer-dependencies'
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $PackagePath = Join-Path $cache ('bouncycastle.cryptography.' + $spec.version + '.nupkg')
    if (-not (Test-Path -LiteralPath $PackagePath)) { Invoke-WebRequest -Uri $spec.url -OutFile $PackagePath -TimeoutSec 60 }
}
foreach ($directory in @($build, $delivery)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $operator = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    foreach ($sid in @($operator.Value, 'S-1-5-18', 'S-1-5-32-544')) {
        $principal = New-Object System.Security.Principal.SecurityIdentifier($sid)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($principal, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $directory -AclObject $acl
}
& $python (Join-Path $source 'prepare_build.py') $PackagePath $build
if ($LASTEXITCODE -ne 0) { throw 'Issuer preparation failed.' }
$output = Join-Path $delivery 'Fly-License-Issuer.exe'
$arguments = @('/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', '/debug-', '/utf8output',
    ('/out:' + $output), ('/win32manifest:' + (Join-Path $source 'app.manifest')),
    ('/win32icon:' + (Join-Path $build 'issuer.ico')),
    '/reference:System.dll', '/reference:System.Core.dll', '/reference:System.Windows.Forms.dll',
    '/reference:System.Drawing.dll', '/reference:System.IO.Compression.dll',
    ('/reference:' + (Join-Path $build 'BouncyCastle.Cryptography.dll')),
    ('/resource:' + (Join-Path $build 'crypto.gz') + ',Fly.License.Crypto'),
    ('/resource:' + $identity + ',Fly.License.Key'), ('/resource:' + $public + ',Fly.License.Public'),
    ('/resource:' + (Join-Path $build 'issuer.ico') + ',Fly.License.Icon'),
    ('/resource:' + (Join-Path $build 'THIRD-PARTY-NOTICES.txt') + ',Fly.License.Notices'),
    (Join-Path $source 'ResourceLoader.cs'), (Join-Path $source 'IssuerCore.cs'),
    (Join-Path $source 'IssuerForm.cs'), (Join-Path $source 'AssemblyInfo.cs'), (Join-Path $source 'Program.cs'))
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw 'Portable issuer build failed.' }
Copy-Item -LiteralPath (Join-Path $build 'THIRD-PARTY-NOTICES.txt') -Destination $delivery
$file = Get-Item -LiteralPath $output
$manifest = [ordered]@{
    tool = 'Fly License Issuer'; version = '1.0.0'; builtAtUtc = [DateTime]::UtcNow.ToString('o')
    file = $file.Name; bytes = $file.Length; sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    internalOnly = $true; containsSigningAuthority = $true; requiresInstallation = $false
    requiresPythonOnTarget = $false; runtime = '.NET Framework 4.8'; privateIdentityRegenerated = $false
    originalFlyPublicKeyMatched = $true; licenseVersion = 1; dependency = $spec
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $delivery 'manifest.json') -Encoding UTF8
Write-Host ('Built internal portable issuer: ' + $output)
Write-Host ('Size: ' + $file.Length + ' bytes; SHA-256: ' + $manifest.sha256)
