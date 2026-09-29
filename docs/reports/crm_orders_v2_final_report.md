# Fly CRM + Orders V2 Final Report

## Scope delivered

- Independent Customer, Order, and Task domains.
- Additive Drift schema v2 migration that preserves Task, Calendar, and Matrix data.
- CRM workspace with Today, next seven days, Inbox, dynamic categories, all customers, and soft-delete projections.
- Customer quick create, fuzzy search, AND-tag filter, sort, priority, recurrence, today-cycle completion, duplicate warning, multiple contacts, follow-up history, next action, Markdown notes, and order summary.
- Dynamic customer categories, statuses, sources, and status/source colors, ordering, activation, and renaming.
- Orders workspace with all, important, normal, tag, and soft-delete projections.
- Order detail with customer link, dynamic status, importance, urgency, priority, dates, tags, reusable Factory/Product items, factory-order state, and missing-order warning.
- Computed sales, costs, tax refund, other income/cost, profit, margin, received, outstanding, and full-payment status using integer minor units.
- Multiple payments, document metadata, local filesystem storage, drag-and-drop/upload, classification, optional payment link, deletion, and system-default opening through a platform adapter.
- Customer ↔ Order navigation with visible customer-filter context.

## Architecture decisions

- Existing shared `tags` is the tag engine; customer and order relationships use separate link tables.
- Customer follow-up completion never completes/deletes the Customer aggregate.
- Financial values use integer minor units. Profit and payment totals are calculated read models, not duplicated truth columns.
- SQLite stores file metadata only. Actual files live below the application-support `FlyData/Orders` tree.
- Order checklist is documented as a later optional aggregate child; it is not required by the V2 core acceptance list and was not added as a fixed workflow.

## Verification

- `flutter analyze`: **0 issues**.
- `flutter test`: **28 tests passed**.
- A physical temporary SQLite file was downgraded to schema version 1, migrated through the production v2 migration, and its pre-existing Task row remained readable.
- UI tests cover today follow-up completion, Customer ↔ Order navigation, missing-factory-order warning, exact profit display, and full-payment display.
- Exact financial fixture: sales 20,000; factory 14,000; inland 500; port 300; other 200; tax refund 1,500 → profit 6,500 and margin 32.5%.
- Exact payment fixture: 5,000 + 10,000 + 5,000 → received 20,000, outstanding 0.

## Windows release

- `flutter build windows --release`: **passed**.
- Executable: `E:\workSpace\fly\build\windows\x64\runner\Release\fly.exe`.
- Portable package: `E:\workSpace\fly\dist\Fly-CRM-Orders-V2-windows-x64.zip` (14,453,300 bytes).
- Package SHA-256: `3BCE150FA088A5A54005569088B8E9AA76EA859602DD615BF21EAB8939A5104C`.
- Customer acceptance screenshot: `E:\workSpace\fly\artifacts\screenshots\crm-orders-v2\customers.png`.
- Order acceptance screenshot: `E:\workSpace\fly\artifacts\screenshots\crm-orders-v2\orders.png`.
- The final non-demo Release was launched for manual testing and left running: PID `9652`, responding at `2026-09-02 08:48:16` (Asia/Shanghai).

## Product acceptance judgment

1. Customer Today immediately identifies who needs contact, with priority and completed-today cycles separated visually.
2. Customer detail exposes identity, stage, latest conversation, next action, and order summary without opening a form dialog.
3. Order detail exposes current status in the first viewport.
4. Missing factory orders are shown both as an order-level warning and an item-level warning.
5. Sales, expected profit, and outstanding receivable are visible in the first viewport; the detailed calculation remains progressively disclosed below.
6. Order files are grouped by document type and open through the operating-system default app within two interactions.
7. CRM and Orders retain Fly's compact rail/sidebar/list/detail interaction rather than adopting an ERP-style data table.
