# Windows 3D spike acceptance

The native renderer spike is integrated at `/tools/container-loading` rather than kept as throwaway code. Acceptance is covered by `container_loading_test.dart` and `container_loading_widget_test.dart`.

- Transparent container and generated box cargo: implemented.
- 1144-package WPC scene: batched into four exact 286-slot sections.
- Orbit, pan, zoom and orthographic presets: implemented.
- Group picking, drag, rotate and collision rejection: implemented.
- Screenshot and copy result: implemented.
- Release build/run: part of the final Windows verification.
