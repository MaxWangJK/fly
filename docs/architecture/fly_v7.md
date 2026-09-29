# Fly V7 Architecture

## Scope

V7 adds data safety, global search, native reminders, typed CRM next actions,
a five-card dashboard, customer Excel import, and unified attachments. Existing
Task, Calendar, Matrix, CRM, and Orders records remain authoritative and are not
recreated.

## Data safety and restore transaction

`FlyBackupService` owns backup policy and packaging. A backup contains a
consistent SQLite snapshot produced with `VACUUM INTO`, `metadata.json`, and all
business directories below the selected FlyData root except backups, SQLite
sidecars, and logs. The default schedule is once per local calendar day with a
seven-day retention window; the user can choose thirty days or another backup
directory.

Restore is deliberately split into two phases:

1. Decode the ZIP in memory, reject unsafe archive paths, validate metadata and
   schema compatibility, then run SQLite `integrity_check` in a temporary
   directory.
2. Create a PreRestore package, remove the widget runtime, close SQLite, move
   current managed data to a sibling rollback directory, promote the verified
   files, reopen Drift, run migrations, and rebuild Riverpod state.

If promotion fails, incoming partial files are removed and the rollback data is
put back before the temporary directories are deleted. A higher schema version
is rejected before current data is touched.

## Database migration 7 → 8

Schema 8 adds:

- `customers.next_action_type`
- `customer_follow_ups.next_action_type`
- `attachments`
- `notification_delivery_logs`

The migration only adds columns and tables. Existing `order_files` rows are
copied with `INSERT OR IGNORE` into `attachments` using `owner_type = order`.
The legacy table remains present as a compatibility source, so no file metadata
is destroyed. New indexes cover attachment owners and notification de-duplication.

## Unified attachments

`AttachmentRepository` stores metadata; `LocalAttachmentStorage` copies bytes
under `FlyData/attachments/<owner-type>/<owner-id>/` and exposes absolute paths
only at the platform boundary. Supported owners are customer, order, payment,
cost, and task. Order file APIs are adapters over the same storage and metadata
model. Widgets coordinate user intent only: select/drop, confirm removal, change
category, or request opening with the default OS application.

## Global search

`GlobalSearchService` queries current Customer, Order, Task, CustomerNote, and
CustomerFollowUp sources. Search covers customer identity/contact fields,
order/customer/product/factory identity, task title/description, notes,
follow-up content, and next-action text/type. Exact matches outrank prefixes,
which outrank contains matches; entity groups provide a second stable ranking
layer. The Ctrl+K palette adds a 200 ms debounce and owns keyboard selection and
route navigation, but contains no database query logic.

## Native reminders

`NotificationService` derives candidates from existing dates only:

- Task: the existing Reminder row.
- Customer: `nextFollowUpDate` at 09:00 local time.
- Order: `deliveryDate` at 09:00 local time.

The Windows gateway uses the installer-aligned AUMID
`Fly.Desktop.Productivity.1`. Each delivered candidate writes the unique tuple
`(entityType, entityId, scheduledTime)` before future checks can repeat it.
Toast payloads route directly to the selected detail. A one-minute coordinator
also watches resume and local day changes, then refreshes Today projections.

## CRM next action

`NextActionType` is a small descriptive value, not a workflow state machine.
CustomerFollowUp remains the history source; Customer caches the latest
non-empty text or type for fast scanning. Type-only follow-ups are valid.

## Dashboard projection

The dashboard stores no rows. `DashboardService` reacts to the existing CRM,
Task, Order, Item, Payment, and Cost tables and returns exactly five projections:
today’s follow-ups, today’s tasks, outstanding orders, urgent orders, and current
month RMB profit. Top-three labels are included for the first four cards.

Current-month profit uses `orderDate`, falling back to `createdAt`, and the local
calendar month. Currency conversion reuses `OrderFinancialSummary`; orders that
need a missing rate are omitted from the profit sum and counted for an explicit
warning rather than being treated as zero.

## Customer import

`CustomerImportService` implements workbook inspection, header inference,
field mapping, validation, duplicate matching, and transactional import. The UI
is a six-step disclosure flow. Normalized Email, WhatsApp, and Phone are exact
duplicate keys; the default action is skip. Statuses, sources, and tags can be
created from incoming text. Preview is capped at twenty visible rows while the
result retains per-row failure reasons.

## Financial presentation rule

Exchange rates are persisted and calculated after rounding to two decimals.
Received, outstanding, and cost summaries display original currencies only.
Conversion remains inside `OrderFinancialSummary` because profit is still a
single RMB result and missing-rate detection must remain reliable.
