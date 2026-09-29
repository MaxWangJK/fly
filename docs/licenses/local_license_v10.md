# V10 offline licensing

## Architecture

`lib/config/feature_flags.dart` owns `ENABLE_LOCAL_LICENSE` (default false).
Enable it for trial distribution and provide `LOCAL_LICENSE_PUBLIC_KEY` as a
base64url raw Ed25519 public key. Missing/invalid keys fail closed; they do not
start a trial. The flag disables the entire gate without changing business data.

`LocalLicenseService` owns UTC expiry and signature policy. `LicenseStorage`
isolates platform access. Windows stores a DPAPI-protected JSON blob under
HKCU `Software\Fly\LocalLicense`, separate from FlyData/SQLite/backups.
First successful protected-state creation starts 72 hours. Each refresh persists
`max(nowUtc, lastSeenUtc)` before making an expiry decision. The gate refreshes
every minute and on resume; live editors stay mounted while locked.

Machine code = uppercase SHA256 of `fly:v1:` plus normalized Windows MachineGuid.
Raw MachineGuid is never displayed or written to business data. This is a
per-Windows-user trial record; switching Windows accounts can start another trial.
Corrupted existing state is an error, not an implicit reset.

License token = base64url(exact UTF-8 JSON bytes) + `.` + base64url(signature).
Verify signature before trusting payload, then validate machine, UTC timestamps,
version 1 and nonce. Invalid new activation does not overwrite an existing key.
No private signing material is present in Dart/native runner or application assets.

## Internal issuer operation

An isolated Python runtime exists at `license_tools/private/runtime/`.
The issuer key was initialized on 2026-09-13. Its file ACL was restricted to the
current Windows user, SYSTEM and Administrators. **Do not run --init again or replace
the key**: releases already built with this public key depend on it.

```powershell
# Internal use only. Use the COMPLETE machine code supplied by the user.
& license_tools/private/runtime/Scripts/python.exe license_tools/generate_license.py --machine <64-hex-code> --days 30
```

Positive integer durations up to 36500 days are accepted. Issuing starts the
duration at generation time, not first activation. The generator emits only the
signed token. Store `license_tools/private/issuer.pem` in a private, backed-up
location and restrict Windows ACLs to authorized administrators/issuer operators.
Do not send the generator, its runtime, or private directory to customers.

```powershell
$flyIssuerPublic = (Get-Content license_tools/public_key.txt -Raw).Trim()
flutter build windows --release --dart-define=ENABLE_LOCAL_LICENSE=true "--dart-define=LOCAL_LICENSE_PUBLIC_KEY=$flyIssuerPublic"
# Internal development only; do not distribute as a protected trial:
flutter build windows --release --dart-define=ENABLE_LOCAL_LICENSE=false
```

The installer includes only `build/windows/x64/runner/Release/*`; issuer files,
private key, Python runtime and obfuscation symbols are outside that tree.

## Limitations and manual acceptance

Offline licensing is a deterrent, not guaranteed DRM. Administrators can remove
registry records, reverse-engineer the binary, reinstall Windows or restore VM
snapshots. Frozen clocks/long offline sessions cannot be authoritatively measured
without a trusted server. Ordinary rollback does not reduce persisted lastSeenUtc.
This module is intended to be replaceable by server licensing later.

No license activation, clock changes, registry corruption, or live app opening
was performed automatically. Manually test on a disposable Windows user/VM:
first launch 72h trial; expiry lock without data deletion; valid activation;
wrong-machine/modified/expired token rejection; restart persistence; ordinary
clock rollback; state write failure; resume; flag-disabled development build;
Chinese/English display. Keep production data and issuer keys out of test VMs.

References: [Dart cryptography 2.9.0](https://pub.dev/packages/cryptography/versions/2.9.0),
[Windows DPAPI](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata).
