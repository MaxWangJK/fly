# Fly CRM / Orders Polish V2 final report

Date: 2026-09-02

## Outcome

Polish V2 is complete without adding a new product module or replacing the existing Riverpod, Repository, Drift, or SQLite architecture. Existing Task, Calendar, Matrix, Customer, Order, payment, file, and migration behavior is retained.

## Delivered

- Customer list tag filters use available-width measurement, render no more than two rows, and place overflow in a checked `更多 ›` popover.
- Customer and Order details share one title-free, outlined, naturally growing tag selector with search, select, Enter-to-create, and unlink behavior.
- Ordinary zero-reference tags are physically collected after link changes or owner soft deletion; task references and active category-owned tags protect a tag from collection.
- Customer Basic Information supports global text, number, and date field definitions plus per-customer values and impact-count deletion confirmation.
- Orders can be created only from Customer Detail; repository validation requires an active customer.
- Order Detail is compact: customer/status, priority/flags, tag container, dates, three summaries, and files. Priority affects sorting/background; Important/Urgent remain small red list text.
- Order details, finance, and notes use mutually exclusive responsive extension panels.
- Order items require factory, product, and quantity, with autocomplete and Enter-to-create. Factory-order-status UI and summary logic were removed while the database column remains migration-compatible.
- Finance is ordered by business workflow. Deposit and balance values derive from payments. Cross-currency profit requires a base profit currency and exchange rate; unavailable rates never produce invalid arithmetic.
- Order notes use a dedicated entity and the shared notes interaction framework, including search, blocks, colors, Enter save, and Shift+Enter newline.
- Existing order file upload, classification, payment attachment, and system-open behavior remains at the bottom of Order Detail.

## Database

Schema version 4 adds customer custom-field definitions/values, order notes, base profit currency, and exchange-rate storage. Migration is additive, guards existing columns, copies legacy order notes, and preserves all existing task/customer/order data. No database drop is used.

## Verification

- `flutter analyze`: PASS, 0 issues.
- `flutter test`: PASS, 45/45 tests.
- `flutter build windows --release`: PASS.
- Visual QA: PASS for Customer Detail, compact Order Detail, Order Details Extension, and Financial Extension.
- Release runtime: PASS; `fly.exe` PID 5280, responding, window title `Fly`.

## Release

- Executable: `E:\workSpace\fly\build\windows\x64\runner\Release\fly.exe`
- Package: `E:\workSpace\fly\dist\Fly-CRM-Orders-Polish-V2-windows-x64.zip`
- Package size: 14,524,524 bytes
- SHA-256: `ADAF14A17AA792C48392A4198162EB43FF1D68F6D6BA8373883D02F222AB2C12`

## Visual evidence

- `docs/screenshots/crm_orders_polish_v2/customer_detail.png`
- `docs/screenshots/crm_orders_polish_v2/order_detail.png`
- `docs/screenshots/crm_orders_polish_v2/order_details_extension.png`
- `docs/screenshots/crm_orders_polish_v2/order_financial_extension.png`

## Product acceptance

The Customer detail is shorter and remains readable. Tag filters no longer grow without bounds. Unused ordinary tags disappear from the database. New orders always start from customer context. Order Detail leads with customer and status instead of finance. Important/Urgent orders are visible in the list. Factory, product, and quantity are available within the details extension without factory status noise. Finance stays simple and refuses invalid cross-currency calculation. Order notes support rapid continuous capture through the same interaction model as customer notes.
