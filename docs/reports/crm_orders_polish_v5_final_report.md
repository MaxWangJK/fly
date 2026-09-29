# Fly CRM / Orders Polish V5 Final Report

Date: 2026-09-04

## Outcome

Polish V5 is complete without adding new business modules or replacing the accepted Task, Calendar, or Matrix workspaces.

- Customer follow-up content and next action can be saved independently with Enter. Shift+Enter keeps a newline. Empty submissions are ignored.
- Follow-up history supports edit and soft delete from the context menu. The customer header always falls back to the latest remaining non-empty next action.
- A/B/C/D are removable tags. Removing the active level tag clears the category relationship, while the customer remains visible in All Customers.
- Each order uses one financial currency marker (USD or RMB/CNY). Switching currency never converts stored values and requires confirmation.
- Payment and cost editors are desktop-sized and inherit the order currency. Type is optional free text.
- The financial panel provides direct cards for Deposit, Balance, Factory Cost, Inland Cost, and Port Charges.
- Customer source moved to the collapsed Basic Information section. The former top field is now compact Customs Information and opens a long-form editor.
- First-run sample data is dynamic and runs once only for a completely fresh database. Any existing customer, order, or task prevents sample insertion.
- The light theme now uses a warm beige canvas, ivory surfaces, sage selection, soft orange/red accents, and rounded compact cards across Customer and Order workspaces.

## Data safety

- Database schema version: 6.
- Existing Task, Calendar, Matrix, Customer, and Order data is migrated in place.
- No startup deletion or database reset exists in production code.
- Existing databases receive a seed-disabled marker during migration; first-run sample data is reserved for a fresh database.
- Follow-up, customer, and order deletion remains soft-delete based.

## Verification

- `flutter analyze`: PASS, no issues.
- `flutter test`: PASS, 77 tests.
- `flutter build windows --release --obfuscate`: PASS.
- `flutter run -d windows --release`: PASS.
- Running executable: `E:\workSpace\fly\build\windows\x64\runner\Release\fly.exe`.
- Runtime check: window title `Fly`, responding normally.

## Visual review

- [Customer detail](../screenshots/polish_v5/customer_detail.png)
- [Order detail](../screenshots/polish_v5/order_detail.png)
- [Order financial panel](../screenshots/polish_v5/order_financial.png)

The screenshots use a fresh in-memory database populated through the production first-run seeder, so they validate the dynamic demo experience without touching user data.

## Windows package

- Installer: `E:\workSpace\fly\dist\Fly-Setup-1.0.0.exe`
- Size: 11,682,689 bytes
- SHA-256: `9E6B49985C0C6FD0B30D3DD5CD517ACA0143CA082E1EF0B76E92A4150B3ED14B`
- Private split-debug symbols remain outside the installer in `E:\workSpace\fly\private_symbols\1.0.0`.

