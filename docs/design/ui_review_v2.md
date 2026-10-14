# UI Review V2

## Todo

- **Information density:** The expanded layout uses a 236 px navigation column and 488 px task column, leaving the remaining width for detail. Standard rows are 44 px rather than cards, so a 720 px-high window exposes roughly 12–13 tasks while retaining readable metadata.
- **Whitespace:** Spacing follows the 4/8/12/16/24/32 scale. Hierarchy comes from white space, a quiet sidebar surface, and low-contrast dividers rather than shadows or large colored panels.
- **Operation steps:** Creating a task is click Add → type → Enter. When the list has keyboard focus, Enter opens the field directly. The field clears and retains focus after creation, so consecutive entry needs no mouse movement.
- **Clarity:** Today, Next 7 days, Inbox, Calendar, Matrix, custom lists, Completed, and Trash have stable positions. Selecting a custom list filters by the persisted `listId`; it does not mix unrelated tasks.
- **Completion feedback:** Completion immediately changes the checkbox, muted title, strike-through, and surface. Repository ordering moves the task below all open tasks while keeping it visible. Toggling again restores the open state and ordering.
- **Compared with mature 任务管理软件-class tools:** Fly now matches the essential desktop scanning and quick-entry loop. It deliberately does not add natural-language date parsing, nested folders, or bulk editing in V1, so advanced capture remains less capable while the common path stays fast.

## Calendar

- **Compactness:** A fixed Sunday-first 7 × 6 grid fills the workspace. Week headings are 24 px and task rows are 25 px, with low-contrast 3 px gutters and no large header.
- **Quick creation:** Clicking a date or the toolbar Add button reveals a single inline field in that cell. Enter creates with the exact `dueDate`, clears the text, and preserves focus; Escape closes it.
- **Visible task volume:** Up to three tasks remain visible in an unselected cell. A selected cell reserves one line for quick entry and shows two tasks plus an overflow count.
- **Month scan:** Leading and trailing dates remain visible but muted. Today uses a small accent circle, while the selected date uses a thin accent edge. Previous, Today, Next, Month view, and Jump to date remain in one compact toolbar.
- **Consistency:** Calendar rows reuse the same checkbox, title, selected, hover, and completed states as Todo. Task clicks open the shared detail panel; drag and drop persists the new date through the same repository.

## Matrix

- **Comfort:** The workspace is a stable 2 × 2 grid on desktop, with 12 px gaps, white cards, restrained radius, and independent scrolling. It remains usable in a narrow window by stacking quadrants.
- **Color restraint:** Red, orange, blue, and green appear only in the 3 px top rule, heading, selection edge, and drop feedback. Card bodies stay neutral.
- **Quadrant clarity:** Every quadrant pairs a direct label with a one-line action hint and count. Importance and urgency are therefore readable without relying on color alone.
- **Task recognition:** Rows are 25 px and use the shared checkbox/title visuals. Completed tasks remain visible at the bottom; drag handles communicate that moving a row updates persisted importance and urgency.

## Global acceptance

- Simplified Chinese is the default locale; English remains available from the sidebar.
- Custom-list create, rename, delete, and persisted filtering are implemented.
- Detail editing auto-saves after 450 ms and serializes overlapping revisions without a Save button.
- Mouse hover, selection, completion, disabled, keyboard focus, context menu, and drag/drop states are distinct.
- Demo data covers realistic Chinese tasks across dates, lists, and all four quadrants.
- Final static analysis, tests, Release build, screenshots, and executable launch are recorded during release packaging.

## Release verification — 2026-09-01

- `flutter analyze`: PASS — no issues found.
- `flutter test`: PASS — 13 tests, including reactive Trash restore/permanent deletion, Completed navigation, and Calendar quick-add visibility.
- `flutter build windows --release`: PASS in the real project directory using Flutter 3.47.2 and Visual Studio 2026.
- `flutter run -d windows --release`: PASS — the final Windows runner launched and remained responsive for user testing.
- `todo_v2.png`, `calendar_v2.png`, and `matrix_v2.png` were regenerated from actual Release runners and visually reviewed at 1280 × 720.
