# Interaction Specification V5

## Navigation and lists

- The icon-only primary rail contains Tasks, Calendar, and Matrix.
- The task sidebar appears only inside Tasks and contains Today, Next 7 days, Inbox, custom lists, Completed, and Trash.
- Switching to Calendar or Matrix removes the entire task sidebar; switching back to Tasks returns to Today.
- A custom list filters the real task stream by `listId`.
- Create and rename reject blank names.
- Deleting a custom list soft-deletes the list and moves its active tasks to Inbox.
- Inbox cannot be renamed or deleted.
- Completed is a reactive active-task query. Trash is a reactive soft-deleted-task query with Restore and confirmed Delete forever actions.

## Quick add

- Click Add task or press Enter while the task list has focus.
- Enter creates a non-empty task, clears the input, and keeps input focus.
- Empty input never creates a task.
- Calendar quick add opens in a lightweight dialog rather than changing cell height. Enter creates the dated task; Escape closes the dialog.
- Escape clears and closes list, Calendar, and Matrix quick add.

## Keyboard

- Up and Down select adjacent tasks.
- Delete soft-deletes the selected task.
- Enter opens quick add.
- Escape clears selection or cancels input.

## Pointer

- Click selects and opens details.
- Right-click offers complete/incomplete, edit, move to list, priority, and delete.
- Calendar drag changes the due date.
- Matrix drag changes importance and urgency.

## Detail editing

The task content field has no redundant Title label, and Notes owns the largest editing area. Priority and Repeat are compact single-choice groups with square check indicators. Importance and Urgency are one-line checkboxes without a redundant Matrix heading.

The next seven dates, starting today, are always visible. The first click chooses the start and the second chooses the due date; reverse-order clicks are normalized. Custom opens the platform date-range picker. All fields update the shared draft and auto-save after 450 ms. The status label communicates waiting, saving, or saved; there is no Save button.

Edits made while a previous SQLite write is still in flight are retained as a newer revision and saved in the next serial pass. A repository stream update never replaces a dirty local draft.
