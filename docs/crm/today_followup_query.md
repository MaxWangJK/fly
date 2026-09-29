# Today Follow-up Query

For a local calendar day `today`:

- Today contains every active customer whose `nextFollowUpDate < tomorrow`, including overdue customers.
- A customer already followed up today remains visible and is sorted after unfinished work.
- Next 7 Days starts tomorrow and ends before `today + 8 days`, so overdue and today items are not duplicated.
- Completing a recurring follow-up calculates the next due date from its recurrence.
- Completing a “从不” recurrence explicitly clears `nextFollowUpDate`; it therefore does not reappear tomorrow.

The repository accepts an optional clock date in `CustomerQuery` so boundary behavior is deterministic in tests.
