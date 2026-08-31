# Interaction Patterns

## High-value patterns

- **Stable shell:** primary navigation remains fixed while content changes.
- **Selection with context:** a right panel edits a task without losing list position.
- **Compact task rows:** completion, title, small metadata, and a drag affordance support high density.
- **Projection-aware drag:** drop targets translate position into model intent.
- **Progressive disclosure:** popups, dialogs, and context menus carry secondary actions.
- **Optimistic-feeling local work:** database writes are local and refresh quickly.
- **Consistent task identity:** one task appears in List, Calendar, and Matrix.

## Drag intent table

| Source/target | Model operation |
|---|---|
| Task list reorder | Update sort order |
| Calendar day | Update due date |
| Matrix quadrant | Update importance/urgency or configured rule fields |
| List/project | Update list/project ID |

Fly applies these patterns with restrained motion and keyboard-friendly controls. It avoids copying TickTick icons, branding, resources, pixel measurements, or proprietary interaction details.
