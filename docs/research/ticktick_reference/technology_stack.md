# Technology Stack

## Observed Windows client

| Area | Observation | Architectural implication |
|---|---|---|
| Runtime | .NET Framework 4.6.2, x64 | Mature Windows-native desktop baseline |
| UI | WPF and XAML | View/ViewModel separation and desktop density |
| State | MVVM, CommunityToolkit.Mvvm, behaviors | Commands and notifications mediate UI actions |
| Storage | SQLite with WAL | Local operations are durable and reactive work can follow commits |
| Desktop integration | NHotkey.Wpf, tray/pipe integrations | OS-specific concerns are separated from task semantics |
| Media/UI helpers | Emoji.Wpf, WPFMediaKit | Optional capabilities sit around the core task product |
| Native boundary | Native and C++/CLI assemblies | Some features cannot be reconstructed from managed code alone |

## Assembly inventory

The working copy contained 257 files: 56 managed assemblies and 51 native PE files were classified, with 84 valid signatures observed. The main project referenced TickTick-owned model, DAO, handler, and utility assemblies alongside third-party UI packages.

## Fly interpretation

Fly does not reuse this stack. Equivalent product concerns are re-expressed with Flutter, Riverpod, GoRouter, Drift, and SQLite. Platform-specific integration is kept outside domain code so Windows-first delivery does not prevent later macOS, Android, and iOS work.
