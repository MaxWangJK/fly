# UI Architecture

## Desktop composition

```text
Sidebar | Primary workspace | Contextual detail
```

The layout keeps navigation stable, gives the current collection most space, and exposes editing without losing list context. Information density is controlled through compact rows, restrained dividers, contextual panels, and popups for secondary choices.

## Responsibility map

| Area | Responsibility |
|---|---|
| Sidebar | Stable destinations, lists/projects, filters and entry points |
| Task list | Query projection, ordering, completion, selection and batch context |
| Task detail | Editing one task and its related checklist/reminders/tags |
| Calendar | Date-bounded projection with month/week/day presentation |
| Matrix | Rule-based quadrant projection and batch property updates |
| Settings | Global application preferences |
| Popup/dialog | Short-lived decisions without displacing the workspace |
| Context menu | Object-specific actions |
| Drag and drop | Intent translation: reorder or update task properties |

## State flow

Selection is presentation state; tasks are durable domain state. A ViewModel reacts to input, delegates to services, and receives notification-driven refresh. Dragging is not stored as pixel position: the target converts it into sort, date, priority, tag, or other task-property changes.

## Fly lesson

Use the three-pane model on wide Windows layouts, collapse the sidebar to a rail at medium width, and navigate details as a page on compact width. Reproduce the information principle, not TickTick's visuals.
