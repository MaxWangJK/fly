# Customer Follow-up Entry V2

The follow-up extension treats the follow-up content and next action as two independent, optional inputs. At least one trimmed value is required.

- `Enter` saves from either input.
- `Shift+Enter` inserts a line break.
- A successful save clears both inputs and restores focus to the main follow-up field.
- No success snackbar is shown; the new history block is the feedback.
- A next-action-only record omits the empty content area.

History blocks expose Edit and Delete from both the trailing menu and the Windows right-click menu. Delete is confirmed and uses `CustomerFollowUps.deletedAt`. Editing or deleting a record recomputes `Customer.lastFollowUpAt` and the latest non-empty `nextAction`, so the customer header never shows deleted or stale content.

