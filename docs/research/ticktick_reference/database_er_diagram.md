# Database ER Diagram

This is an architectural abstraction of the researched relationships, not a copy of proprietary schema DDL.

```mermaid
erDiagram
  LIST ||--o{ TASK : contains
  TASK ||--o{ CHECKLIST_ITEM : owns
  TASK ||--o{ REMINDER : schedules
  TASK ||--o{ ATTACHMENT : owns
  TASK ||--o{ TASK_TAG : labeled
  TAG ||--o{ TASK_TAG : applies
  TASK o|--o{ TASK : parent_of
  TASK ||--o{ SYNC_RECORD : tracks
  LIST ||--o{ SYNC_RECORD : tracks

  TASK {
    string business_id
    string list_id
    string parent_id
    string title
    int status
    bool deleted
    datetime due_date
    int sort_order
    string etag
    datetime modified_time
  }
  CHECKLIST_ITEM {
    string task_id
    string title
    int status
    int sort_order
  }
  REMINDER {
    string task_id
    datetime remind_at
  }
  SYNC_RECORD {
    string entity_id
    string operation
    string revision
  }
```

The key lesson is separation: main task fields, many-to-many tags, ordered children, scheduled reminders, and sync bookkeeping evolve independently.
