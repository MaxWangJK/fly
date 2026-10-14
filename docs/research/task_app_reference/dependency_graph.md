# Dependency Graph

```mermaid
graph TD
  EXE[ReferenceApp.exe / WPF shell]
  EXE --> MODELS[ReferenceAppModels]
  EXE --> DAO[ReferenceAppDao]
  EXE --> HANDLER[ReferenceAppHandler]
  EXE --> UTILS[ReferenceAppUtils]
  DAO --> MODELS
  HANDLER --> MODELS
  HANDLER --> NATIVE[Native interop]
  MODELS --> SQLITE[SQLite]
  EXE --> MVVM[CommunityToolkit.Mvvm]
  EXE --> BEHAVIOR[Microsoft.Xaml.Behaviors]
  EXE --> UIHELP[Emoji.Wpf / NHotkey.Wpf / WPFMediaKit]
```

## Reconstruction evidence

- `ReferenceAppUtils`, `ReferenceAppModels`, and `ReferenceAppDao` built successfully.
- `ReferenceAppHandler` reached C++/CLI and Kotlin-native interop errors.
- The main WPF project reached resource generation, then stopped on a missing `System.Resources.Extensions` requirement for preserialized non-string resources.
- Native `SmartDateDLL` was correctly identified as non-managed and was not treated as C#.

The graph explains why managed core assemblies can build while a complete executable remains blocked by native and resource edges.
