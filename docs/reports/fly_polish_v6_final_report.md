# Fly Polish V6 Final Report

Date: 2026-09-04

## Outcome

Fly Polish V6 is complete while preserving the accepted Task, Calendar, Matrix, CRM, and Orders workspaces.

- Order finance now supports independent USD/RMB currency selection for sales, tax refunds, factory costs, costs, and payments.
- Each order stores a manual USD-to-RMB rate. Mixed-currency totals, received amounts, outstanding amounts, estimated profit, and margin are calculated consistently; RMB profit stays unavailable when a required rate is missing.
- The financial detail follows the business reading order: receivable and payment rows, received summary, cost rows, cost summary, tax refund, then RMB profit and margin.
- Order level is reduced to one exclusive control: General, Important, or Urgent. List rows show only the effective level using a small accent.
- Customer priority remains independent. Rows use a neutral background with a compact High, Medium, or General marker.
- Customer source appears directly after City in Basic Information.
- Order production items can be edited or deleted from the card menu. The editor covers factory, product, quantity, unit, factory cost, and cost currency.
- Excel export provides Customers, Orders, OrderItems, Payments, and Costs worksheets, with stable relation IDs, numeric money fields, currency columns, readable widths, bold headers, and frozen first rows. Attachment contents are intentionally excluded.
- Five persistent color palettes are available: Fly Default, Graphite, Warm Sand, Ocean, and Forest.
- Task quick input is always visible. Enter creates and keeps focus; Escape clears and releases focus.
- The Windows runner opens a 1280 x 720 window centered in the primary monitor work area.

## Data safety

- Database schema version: 7.
- Migration adds `tax_refund_currency` and `factory_cost_currency` without dropping or recreating tables.
- Existing Task, Calendar, Matrix, CRM, Order, payment, cost, file, and setting data is retained.
- Existing V6 order currency values are propagated into the newly introduced per-value currency columns.
- Production startup contains no database reset or destructive seed path.

## Verification

- `flutter analyze`: PASS, no issues.
- `flutter test`: PASS, 86 tests.
- Schema V6 to V7 migration test: PASS.
- Financial conversion, missing-rate, mixed-payment, item-edit, Excel relationship/freeze, theme persistence, task quick-input, and neutral customer-row tests: PASS.
- `flutter build windows --release --obfuscate --split-debug-info`: PASS.
- Windows installer build and SHA-256 generation: PASS.
- `flutter run -d windows --release`: PASS and intentionally left running for user testing.
- Release runtime: PASS. Window title `Fly`, process responding normally (launch PID 4644).
- Startup centering: PASS. The 1280 x 720 window opened at `(320, 160)` in a 1920 x 1040 primary work area; measured center delta `X=0, Y=0`.

## Visual review

- [Customer detail](../screenshots/polish_v6/customer_detail.png)
- [Order detail](../screenshots/polish_v6/order_detail.png)
- [Order financial detail](../screenshots/polish_v6/order_financial.png)

The screenshots use an isolated in-memory database and do not touch the user's production data.

## Windows package

- Installer: `E:\workSpace\fly\dist\Fly-Setup-1.0.0.exe`
- Size: 11,829,821 bytes
- SHA-256: `C4F8651AD150C1E147613B125BF3378B2A2C74C6D04C4371C45F22BA87B609F4`
- Release executable: `E:\workSpace\fly\build\windows\x64\runner\Release\fly.exe`
- Private split-debug symbols: `E:\workSpace\fly\private_symbols\1.0.0`

## Product acceptance

- Customer work remains calm and scannable: neutral rows, concise priority cues, and source information placed with the rest of the basic profile.
- Order work answers the key questions in one reading path: current level, production ownership, amounts received, costs incurred, RMB profit, and missing exchange-rate action.
- Per-entry currencies remove the ambiguity of a single global accounting switch without turning Fly into a traditional ERP form.
- Editing stays progressively disclosed through detail panels and compact popovers/dialogs.
- Exports preserve relationships for downstream analysis while avoiding embedded files and oversized workbooks.
