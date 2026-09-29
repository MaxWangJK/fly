# 3D engine evaluation and spike

Evaluated for Flutter 3.47.2 desktop:

| Option | Windows | Mouse/picking | Instancing | macOS path | V1 decision |
| --- | --- | --- | --- | --- | --- |
| Flutter native CustomPainter | Native | Full pointer control | Batch/group drawing | Native | Selected |
| Flutter scene packages | Package-specific | Varies | Varies | Varies | Rejected for V1 risk |
| OpenGL renderer/plugin | Possible | Custom | Strong | Requires backend work | Future option |
| WebView + Three.js/Babylon.js | Good | Strong | Strong | Good | Rejected: runtime/bridge weight |

## Spike result

The production scene is also the spike result:

1. Transparent programmatic container: pass.
2. 1000+ packages: pass through group batch rendering; 1144 WPC packages render as four section cuboids plus grid lines.
3. Orbit and zoom: pass.
4. Group picking: pass using projected AABB bounds.
5. Drag: pass with 50 mm grid snap, surface snap and invalid red outline.
6. Windows release: verified in the release gate.

The approach has no model copyright risk, keeps precise geometry, and adds no third-party 3D runtime. GLB remains a future visual layer only.
