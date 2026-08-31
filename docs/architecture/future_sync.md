# Future Sync

Fly V1 does not sync. The schema prepares rather than pretends:

- UUID IDs can be created offline.
- `version` supports local optimistic/concurrency decisions.
- timestamps support change windows.
- `deletedAt` can become a tombstone.
- repository commands form a future operation boundary.

Before implementation, specify identity/accounts, encryption, server trust, revision semantics, conflict rules, tombstone retention, retry/idempotency and observable sync state. Add a dedicated operation log rather than inferring every change from `updatedAt`.
