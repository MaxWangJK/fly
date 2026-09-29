# Container loading dependency record

The V1 container-loading implementation adds no third-party renderer or packing library.

| Package/technology | Version | License | Usage |
| --- | --- | --- | --- |
| Flutter framework / CustomPainter | Project SDK 3.47.2 | BSD-3-Clause | Native scene, mouse and canvas rendering |
| Drift | Existing project dependency | MIT | Presets, cargo and loading-plan persistence |
| Riverpod | Existing project dependency | MIT | Workspace state/repository injection |
| uuid | Existing project dependency | MIT | Cargo, plan and group identifiers |

Packing, orientation, AABB, snap and multi-SKU slab heuristic code is original Fly code. No third-party models or external algorithm source were copied. `assets/3d` contains placeholders only; V1 geometry is generated programmatically.
