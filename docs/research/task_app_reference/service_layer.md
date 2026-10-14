# Service Layer

Services coordinate operations that cross a single table or require cache, notification, or sync consequences.

## Complete-task example

```mermaid
sequenceDiagram
  participant UI
  participant VM as ViewModel/Command
  participant S as TaskService
  participant DAO as TaskDao
  participant DB as SQLite
  participant Sync as SyncStatusDao
  participant N as Notifier/Cache
  UI->>VM: Complete task
  VM->>S: SetTaskStatus
  S->>DAO: Load current task
  S->>S: Resolve recurrence branch
  S->>DAO: Update task and related checklist/subtasks/reminders
  DAO->>DB: Transactional writes
  S->>Sync: Mark local change
  S->>N: Publish task change / invalidate cache
  N-->>UI: Refresh projection
```

## Observed responsibilities

- TaskService handles status transitions and recurrence behavior.
- CalendarService prepares calendar projections.
- DAOs handle concrete persistence.
- Notifiers prevent views from polling.
- SyncStatusDao records deferred remote work.

## Fly lesson

V1 needs less ceremony. Its repository coordinates task and child-entity writes directly in Drift transactions. A separate service should only be introduced when recurrence expansion, conflict resolution, or another truly cross-cutting workflow arrives.
