# Desktop Layout V4

## Expanded

```text
52 primary rail | 236 module sidebar | 488 compact list | flexible detail
```

Customer, Order, and Task routes preserve four visually separate regions. The primary rail switches product modules. Each module owns its sidebar projections and list state. The right pane shows the selected aggregate or an instructional placeholder.

Calendar and Matrix use `52 primary rail | flexible workspace`. They never render the task sidebar.

## Medium

At 760–1099 px, the 52 px icon rail remains visible. Customer, Order, and Task workspaces keep their 236 px module sidebar while the list occupies the remaining workspace. Calendar and Matrix continue to omit secondary navigation.

## Compact

Below 760 px, bottom navigation exposes Customer, Order, Task, Calendar, and Matrix. Matrix cards stack below 700 px.

## Scrolling and resizing

The task-sidebar list section, task list, detail editor, and each Matrix quadrant own independent scroll views. Completed and Trash remain pinned below the independently scrolling custom-list area. Long task and list names ellipsize. The calendar derives a 7 × 6 grid ratio from available size and does not change weekday ordering during resize.

The system title bar is retained in V4 to avoid regressions in drag, maximize, minimize, and resize behavior. A custom title bar remains a separately testable enhancement.
