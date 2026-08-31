# Database Schema

The local TickTick database was inspected read-only through `sqlite_master` and `PRAGMA`; no task content rows were read. WAL is enabled during startup. The application creates many tables and indexes, including task-status/deletion and task-detail date indexes.

## Conceptual entities

| Entity | Purpose | Important design fields |
|---|---|---|
| Task | Primary work item | business/server IDs, project/parent IDs, status, deleted, sort, dates, version metadata |
| Project/List | Task grouping | stable ID, sort, status/deletion |
| Tag / TaskTag | Many-to-many labels | tag ID, task ID, normalized name |
| TaskDetail / Checklist | Child steps and extended task data | task ID, status, sort, dates |
| Reminder | Scheduled task notification | task ID, trigger time, status |
| Settings | Local preferences | key/value or typed settings |
| Sync status/queue | Deferred remote mutations | entity ID/type, operation/revision/dirty state |
| Attachment | Related local/remote material | task ID, metadata and server state |

## Persistence patterns

- A local numeric key may coexist with a stable string business ID.
- Relations are commonly maintained by ID convention rather than enforced foreign-key constraints.
- Soft deletion and status columns keep records available for synchronization.
- Indexes follow query shapes: active tasks by status/deleted, list and sort, and dated details.
- Server IDs, etags, revisions, or dirty flags support eventual synchronization.

Fly improves local referential integrity by enabling SQLite foreign keys, while retaining UUID IDs, soft deletion, versions, timestamps, and query-specific indexes.
