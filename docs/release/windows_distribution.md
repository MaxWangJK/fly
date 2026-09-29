# Windows Distribution

Fly ships as a per-user x64 Windows 10+ installer built with official Inno Setup.

## Build

Run `scripts/build_installer.ps1`. It executes dependency restore, static analysis, all tests, and an obfuscated Windows release build from the same source revision. It supplies the `pubspec.yaml` version and build number to the app, and explicitly enables offline licensing with the repository's public key. The installer script no longer accepts a skip-build option that could package an old executable. Dart split-debug symbols are written to `private_symbols/<version>` and excluded from Git and the installer.

Obfuscation only increases reverse-engineering difficulty. It does not provide absolute source-code protection.

The installer is written to `dist/Fly-Setup-<version>-build<build-number>.exe`, with a separate SHA-256 file and testing notes. Build-numbered filenames avoid overwriting older candidate installers. Source, tests, docs, build intermediates, and private symbols are not packaged.

## Install behavior

- Default path: `%LOCALAPPDATA%\Programs\Fly`
- Start Menu shortcut and default-selected desktop shortcut
- Optional launch after setup
- Standard Add/Remove Programs uninstall entry
- Uninstall never deletes the configured FlyData root or user settings

On first run, the user selects the data root. `Documents\FlyData` is recommended. The workspace is blank by default; demo records require an explicit opt-in. The root contains `fly.db`, managed files, `attachments`, `orders`, `customers`, `backups`, and `logs`. Existing legacy `fly.sqlite` data is copied and retained at the old path as a rollback source. Backup ZIPs that include the managed file library must be moved together with the `.fly-file-objects` directory in the backup location.

## Runtime and signing

The installer detects `VCRUNTIME140.dll` and warns if the Microsoft Visual C++ 2015–2022 x64 runtime is absent. Install the current runtime from Microsoft before deploying broadly.

No Authenticode certificate is stored in this repository. Unsigned test installers can show Windows SmartScreen “Unknown Publisher”. Sign the final installer with an organization-owned code-signing certificate before broad external distribution.
