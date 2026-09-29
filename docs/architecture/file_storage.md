# Order File Storage Plan

SQLite stores metadata only. Binary content is copied to an application-data storage root selected by a platform storage adapter.

```text
FlyData/
└─ Orders/
   └─ <order-id>/
      ├─ PI/
      ├─ CI/
      ├─ PL/
      ├─ CO/
      ├─ Payments/
      └─ Other/
```

The domain stores no Windows-specific base path. `OrderFileStorage` resolves the platform root, sanitizes names, resolves collisions, copies files, returns metadata, and opens files through `SystemFileLauncher`. The Windows implementation is isolated in the infrastructure adapter; future macOS/mobile adapters can replace it without changing Order business logic.

`order_files` stores ID, Order ID, optional Payment ID, stored filename, original filename, MIME type, document type, local relative path, size, and timestamps.

V1 supports picker upload, desktop drag/drop, classification changes, optional Payment linkage, and opening in the operating system's default application. It does not embed PDFs or store BLOBs.
