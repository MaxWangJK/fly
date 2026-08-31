# Data Flow

## Create/edit task

```mermaid
sequenceDiagram
  participant W as Widget
  participant P as Riverpod
  participant R as Repository
  participant D as Drift
  participant S as SQLite
  W->>P: User intent
  P->>R: Command
  R->>D: Typed write / transaction
  D->>S: Commit
  S-->>D: Query invalidation
  D-->>P: Updated stream
  P-->>W: Rebuild projection
```

## Projection consistency

Todo, Calendar and Matrix subscribe to different repository queries over the same `tasks` table. Calendar drag updates `dueDate`; Matrix drag updates `importance` and `urgency`; list reorder updates `sortOrder`. No view creates a duplicate task type.
