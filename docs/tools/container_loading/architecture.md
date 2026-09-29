# Container Loading Planner architecture

The module is isolated under `lib/features/tools/container_loading` and follows Fly's data/domain/presentation boundaries.

- Data: Drift repositories persist presets, cargo packages, plans and group transforms.
- Domain: all measurements are integer millimetres and grams. Packing and collision code imports no renderer.
- Presentation: the workspace owns input state; `ContainerSceneController` is the renderer boundary.
- Rendering: V1 uses a native Flutter batched projection. One cargo section is one rendered cuboid with grid subdivisions, so 1144 packages do not become 1144 widgets.

Database schema 9 only creates new tables. Existing CRM, Orders, Tasks, Calendar and Matrix tables are untouched. Fly backup already includes the database, so loading plans participate automatically.

## Main entities

`ContainerPreset -> LoadingPlan -> LoadingPlanGroup -> CargoPackage`

The database stores only domain values and transforms. It never serializes a canvas object, mesh or camera.

## Renderer boundary

`ContainerSceneController` exposes scene data, selection, camera, move, rotation, undo/redo and display controls. `NativeContainerSceneController` is the current implementation. A future GPU renderer can implement the same contract without changing packing or persistence.
