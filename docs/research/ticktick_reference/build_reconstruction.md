# Build Reconstruction

## Goal

Reconstruction was used only to test architectural understanding. It was not intended to modify or redistribute TickTick.

## Work performed

ILSpy command-line tooling 9.1.0.7988 was installed into the isolated research workspace. Managed assemblies were decompiled for static inspection. The main project targeted .NET Framework 4.6.2 WPF and referenced CommunityToolkit.Mvvm, Microsoft.Xaml.Behaviors, Emoji.Wpf, NHotkey/Wpf, WPFMediaKit, SQLite, TickTick-owned assemblies, and native components.

Standalone Visual Studio MSBuild initially failed SDK resolution. Rebuilding through the installed x86 .NET host advanced the reconstruction.

## Results

| Component | Result |
|---|---|
| TickTickUtils | Built successfully |
| TickTickModels | Built successfully |
| TickTickDao | Built successfully |
| TickTickHandler | Blocked at C++/CLI / Kotlin-native interop types and calling conventions |
| TickTick main WPF | Reached resource generation; blocked by `System.Resources.Extensions` / preserialized non-string resource requirements |
| SmartDateDLL | Native module; not a managed decompilation target |

Build logs remain in the isolated `TickTick_RE/04_build_logs` research workspace and are not a Fly runtime dependency.

## Rating

**B — Core assemblies can build.**

The core managed model, utility, and DAO layers were reconstructed sufficiently to validate their boundaries. Full application recovery would require proprietary native and resource edges and is not valuable for Fly. Research stops here.
