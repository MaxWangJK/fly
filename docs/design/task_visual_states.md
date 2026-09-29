# Task Visual States V5

| State | Surface | Title | Indicator |
| --- | --- | --- | --- |
| Default | Transparent/white | `#202124` | None |
| Hover | `#F7F7F8` | Normal | Pointer cursor |
| Selected | `#F0F1F3` | Normal | 2 px blue flight-path line |
| Focused | Same selection language | Normal | Keyboard-selected row |
| Completed | `#F8F8F8` | Muted and struck through | Checked checkbox |
| Disabled | `#F7F7F8` | Muted | Disabled checkbox and basic cursor |
| Dragging | Elevated white feedback | Normal | Drag handle |
| Drop target | Subtle semantic tint | Normal | Semantic border |

Completed tasks remain visible in all active task views and are ordered after open tasks in the repository query, not by presentation-only sorting. Trash uses the disabled state because deleted records cannot be edited before restoration. List, Matrix, Completed, and Trash share `FlyTaskRowSurface`; Calendar uses a denser colored event-strip variant while preserving the same completion and selection semantics.
