# Fly

Fly is a Windows-first, cross-platform-ready, local-first task manager built with Flutter, Riverpod, GoRouter, Drift and SQLite.

One durable Task record powers Todo, Month Calendar and Eisenhower Matrix views. The application works offline and has no account or server dependency.

## V1

- Inbox, Today, Upcoming and Lists navigation
- Task CRUD, completion, reorder and rich detail editing
- Month calendar with date selection, quick add and drag-to-reschedule
- Eisenhower Matrix with drag-to-reclassify
- Compact, medium and expanded responsive layouts
- System, light and dark themes
- Real local SQLite persistence

## Development

Required SDK for the current baseline:

```text
Flutter 3.47.2 stable
Dart 3.13.2
Windows 10 x64
Visual Studio Community 2026 18.9.2
Windows SDK 10.0.26100.0
```

Run validation:

```powershell
E:\workSpace\flutter\bin\flutter.bat pub get
E:\workSpace\flutter\bin\flutter.bat analyze
E:\workSpace\flutter\bin\flutter.bat test
E:\workSpace\flutter\bin\flutter.bat run -d windows
E:\workSpace\flutter\bin\flutter.bat build windows --release
```

Flutter plugins require Windows symbolic-link support. Enable Windows Developer Mode before Windows run/build.

## Platform status

| Platform | Status |
|---|---|
| Windows | Development active; analyze/tests verified; run/build blocked until Developer Mode is explicitly enabled |
| Android | Not configured |
| macOS | Not verified — requires macOS |
| iOS | Not verified — requires macOS and Xcode |

Generated platform source is not equivalent to platform verification.

## Architecture

```text
Flutter UI
  -> Riverpod application/query state
  -> TaskRepository
  -> Drift
  -> SQLite (single source of truth)
  -> reactive streams back to every view
```

See [docs/README.md](docs/README.md) for product, architecture, design and reference documentation.
