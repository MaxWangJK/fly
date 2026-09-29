# Fly V10 staged architecture

This is the forward implementation plan, not a completion claim. Keep Riverpod,
Drift, SQLite, existing route ownership and the current design/theme systems.

## Already implemented in source

- `TaskDateRange` defines inclusive local days, a single endpoint means one day.
  The SQL adapter selects intersecting ranges while the Calendar uses the same
  domain interpretation for each cell. Completion remains one record update.
- Today workspace projects active and overdue tasks separately; overdue sorting
  is due descending. Postponement rechecks live rows in one transaction and leaves
  historical start dates unchanged.
- CRM create accepts category context and adds its category tag atomically.
  Active customer names compare trimmed, whitespace-collapsed and case-folded.
  Existing legacy duplicates are not deleted or merged. Changing unrelated fields
  on legacy rows is allowed; new duplicate names and duplicate renames are rejected.
- Source editing is free text at the UI boundary; existing source IDs are reused
  internally so old records are preserved without a source migration.

## Schema 12: note tags (implemented, isolated migration tested)

- Adds NoteTagLinks only; preserves shared tag definitions and independent FileTags.
- Note references, including soft-deleted notes, prevent orphan cleanup. Explicit
  global deletion is blocked while note references exist; remove those links from
  their notes first. This prevents CRM deletion from silently erasing note tags.
- Note tags are normalized at entry, shared by ID and included in note search.
  Tags update separately from block revision so editing tags cannot overwrite an
  unsaved block draft. No live database migration was used for verification.

## Next additive migration (not executed yet)

- WorkspaceNotes.manualSortOrder: nullable integer. Unset folders sort by creation
  descending; the first manual action materializes order for that folder.
- DailyReviews: stable local date key, structured answers, created/updated times
  and revision. Summary figures remain calculated, never copied into Tasks.
- Keep existing FileTags/FileTagLinks independent. Global tag search aggregates
  matching names across engines without rewriting IDs or duplicating ownership.
- Test migration from schema 11 with existing tasks, attachments, notes, blocks,
  draft AppSettings and backup manifests. Do not run migration against live data
  as a test fixture.

## Search

Permanent search entry is independent of optional navigation destinations. Note
body search reads actual text/captions/table cells, not raw JSON IDs. Tag results
must distinguish record counts by customer/order/file/note, and navigation should
carry an explicit tag filter rather than pretending ordinary text search is an
exact tag association filter.

## Daily review

Task sidebar destination, not a primary module. Four lightweight sections retain
the nine requested prompts. Save serially with recoverable failure state. Summary
counts must define completed-today by completedAt, follow-ups by recorded time,
and order changes by updatedAt until a richer event log is explicitly required.
The user-selected reminder is opt-in and uses the existing reminder adapter.

## Files / Notes

### Daily Review implementation checkpoint (2026-09-12)

Schema 13 adds an independent DailyReviews table keyed by local calendar date.
Nine answers are stored as JSON; each answer update merges transactionally and
increments a revision without replacing answers edited in another field.
In-memory sessions retain failed writes for retry across date navigation, and
the existing window-close guard flushes review sessions before permitting exit.
Task sidebar navigation opens a full-width review page with seven recent dates.

Historical summaries query current business records: completed/followed-up counts
use their event timestamps, while open-task state and order updatedAt are not
historical snapshots. The page explicitly communicates that limitation.
The existing reminder adapter delivers an opt-in, configurable local-time review
reminder (default off), deduplicated by date even when the reminder time changes.
Native Windows delivery still requires platform acceptance testing.

Files: small default, medium, single-line list; optional selection preview adapts
to narrow layouts. Customer file aggregation follows actual customer/order/payment
relations, not copied FileTags. Folder arrows and name selection stay separate.
Notes: title-only list, detail timestamps, bottom tags, slash menu; preserve all
existing quote/code content even when those types are removed from creation menus.

## 3D and licensing

Manual placement must not trigger section packing. Out-of-container groups remain
part of the plan; nullable section identity represents staging. Confirmed overflow
keeps actual dimensions and a warning, never a shrunken visual substitute.
Camera direction belongs in the controller.

License: build flag isolates the gate, protected trial state is separate from
business data, and the client contains only a public verification key. Private
keys/generator stay outside installers. Offline rollback defense is not protection
against administrator tampering, OS reinstallation or VM snapshot rollback.

## Verification boundary

The user's later instruction overrides the original automatic testing sequence:
format, compile and package, then supply a manual checklist. Do not run analyzer,
regressions or native acceptance automatically. Preview packaging is not a claim
that V10 is complete. Do not replace or open the user's installed application or
business database as a substitute for manual acceptance.
