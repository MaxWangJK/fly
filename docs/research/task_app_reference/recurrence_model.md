# Recurrence Model

The researched task model includes recurrence rule information, a recurrence origin, exclusions, and end conditions. Completion logic branches when a task repeats.

## Conceptual lifecycle

```mermaid
flowchart TD
  R[Recurrence rule] --> O[Occurrence calculation]
  E[Exclusion dates] --> O
  End[End date/count] --> O
  O --> Due[Current/next due time]
  Due --> Complete[Complete occurrence]
  Complete --> HasNext{Another occurrence?}
  HasNext -- yes --> Advance[Advance or create next occurrence]
  HasNext -- no --> Finish[Series complete]
```

## Design requirements

- Preserve the original recurrence rule separately from a computed due date.
- Define timezone and all-day semantics explicitly.
- Track exceptions without rewriting the whole rule.
- Make completion behavior deterministic.
- Reschedule reminders when occurrence dates move.

Fly V1 reserves `recurrenceRule` and `recurrenceEndAt` on Task and offers simple repeat choices in detail UI. Full RFC-style calculation and exception editing are out of V1 scope.
