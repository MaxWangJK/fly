# Customer Follow-up Recurrence

The customer UI exposes exactly five typed values:

- `never` — 从不
- `every3Days` — 三天
- `weekly` — 每周
- `biweekly` — 两周
- `monthly` — 每月

The single-select control uses compact square check marks and wraps when needed.

The recurrence engine uses `nextFollowUpDate` as its base when present and today's local calendar date otherwise. Three-day, weekly, and biweekly rules add 3, 7, and 14 days. Monthly recurrence uses calendar-month arithmetic with end-of-month clamping, including leap years.

Legacy `daily`, `weekdays`, and `custom:*` values remain readable and map to the supported three-day rule when loaded.
