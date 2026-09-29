# Order Financial Entries

Fly financial capture is an operational log, not an accounting subsystem.

## Payments

`OrderPayment.paymentType` is free text. The UI asks only for amount, type, date, and optional attachment. Existing method/note columns remain for backward compatibility but are hidden. Payments can be edited or soft deleted.

## Costs

`OrderCostEntry` stores amount in minor units, currency, free-text cost type, date, optional attachment, and timestamps. Schema v5 copies legacy inland, port, and other cost fields into cost entries without removing the original values.

## Currency

RMB/CNY and USD are selectable accounting currencies. Changing the selector affects only new records. Existing entries retain their currency. Summaries filter by normalized currency and never add USD to RMB. Sales are converted only when the order has the required exchange rate.

Factory item cost and tax refund remain in the order's profit currency. Profit is sales converted to that currency, minus factory and cost entries, plus tax refund and other income.

Attachments are copied beneath the configured Fly data root; SQLite stores metadata and relative paths only.
