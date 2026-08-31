# Task Model

The researched model combines a local database identity with a string business identifier. It includes list/project and parent relationships, title/content, priority, dates, status, soft deletion, sort order, recurrence data, exclusions, reminders, checklist/detail children, tags, attachments, etag, and created/modified/completed timestamps.

## Conceptual model

```mermaid
classDiagram
  class Task {
    businessId
    projectId
    parentId
    title
    content
    priority
    status
    deleted
    startDate
    dueDate
    sortOrder
    repeatFlag
    repeatFrom
    exDates
    etag
    createdTime
    modifiedTime
    completedTime
  }
  Task "0..*" --> "1" List
  Task "0..*" --> "0..*" Tag
  Task "1" --> "0..*" ChecklistItem
  Task "1" --> "0..*" Reminder
  Task "1" --> "0..*" Attachment
  Task "0..*" --> "0..1" Task : parent
```

## Design ideas

- Business IDs are stable beyond one database file.
- Soft deletion keeps sync history possible.
- Sort order is persisted domain data.
- Related collections are not packed into the main row.
- Server metadata is distinct from user-visible status.

Fly adopts UUID business IDs, soft deletion, versions, relation tables, and explicit sort order. It independently separates priority from matrix importance and urgency.
