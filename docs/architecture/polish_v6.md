# Fly Polish V6 architecture note

## Financial model

- `orders.currency` remains the sales currency and the legacy priority column is retained.
- `orders.tax_refund_currency` and `order_production_items.factory_cost_currency` add per-amount currency metadata.
- Payments and dynamic costs keep their existing per-row currency fields.
- `exchange_rate_micros` is the manual, per-order USD-to-RMB rate. Zero means no rate was supplied.
- Profit is calculated, never treated as a second source of truth: `salesRmb + taxRefundRmb + otherIncomeRmb - totalCostRmb`.
- A non-zero USD value makes RMB profit unavailable until the order rate exists.

## Migration

Schema 7 adds only nullable-safe/defaulted columns. Existing V6 uniform-currency data is propagated into the two new fields. No table is dropped and Task, Calendar, Matrix, CRM, Orders, files and settings remain intact.

## UI state

- Order level is projected from the retained `importance` and `urgency` columns as one exclusive choice: general, important or urgent.
- Theme palette is a `ThemeExtension` and a Riverpod setting. The selected palette ID is stored in `app_settings`.
- Excel export is a read-only projection across Customers, Orders, OrderItems, Payments and Costs; relation IDs remain present and attachments are excluded.
- Task quick add is a persistent list control. Context decides list and due date; Enter creates and retains focus, Escape clears and releases focus.
