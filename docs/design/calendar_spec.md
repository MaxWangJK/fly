# Calendar Specification V5

- Month view is a fixed 7-column × 6-row grid.
- Week order is Sunday through Saturday in both Chinese and English.
- The 42-day query includes leading and trailing dates.
- Non-month dates are muted but interactive.
- Cells share continuous one-pixel borders with no card gaps or rounded corners.
- Today uses a compact blue circle; the selected date uses a quiet blue surface tint.
- The compact toolbar provides Add, Month view, Previous, Today, Next, and More/Jump to date actions.
- No quick-add field is rendered inside a day cell. Clicking a day or Add opens a centered lightweight editor with the date and Inbox context.
- Enter creates a due-dated task and closes the editor; Escape cancels it.
- Calendar task rows are 22 px colored event strips. Text, tint, and the compact square checkbox share one semantic color while completed styling remains visible.
- Direct drag and drop changes `dueDate`.
- Selecting a task opens the shared detail panel at the right on expanded layouts.
- Month changes use a restrained cross-fade without moving the surrounding shell.
