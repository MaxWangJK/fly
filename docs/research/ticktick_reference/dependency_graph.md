# Dependency Graph

```mermaid
graph TD
  EXE[TickTick.exe / WPF shell]
  EXE --> MODELS[TickTickModels]
  EXE --> DAO[TickTickDao]
  EXE --> HANDLER[TickTickHandler]
  EXE --> UTILS[TickTickUtils]
  DAO --> MODELS
  HANDLER --> MODELS
  HANDLER --> NATIVE[Native interop]
  MODELS --> SQLITE[SQLite]
  EXE --> MVVM[CommunityToolkit.Mvvm]
  EXE --> BEHAVIOR[Microsoft.Xaml.Behaviors]
  EXE --> UIHELP[Emoji.Wpf / NHotkey.Wpf / WPFMediaKit]
```

## Reconstruction evidence

- `TickTickUtils`, `TickTickModels`, and `TickTickDao` built successfully.
- `TickTickHandler` reached C++/CLI and Kotlin-native interop errors.
- The main WPF project reached resource generation, then stopped on a missing `System.Resources.Extensions` requirement for preserialized non-string resources.
- Native `SmartDateDLL` was correctly identified as non-managed and was not treated as C#.

The graph explains why managed core assemblies can build while a complete executable remains blocked by native and resource edges.
