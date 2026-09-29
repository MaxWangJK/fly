# Simple Order Financial Currency

Each order has one financial currency: `CNY` (shown as RMB) or `USD`. The existing `Orders.currency` column is the source of truth. Legacy profit-currency and exchange-rate columns remain only for backward-compatible storage and are normalized to the same currency.

The selected currency applies to the order amount, tax refund, other income, payments, costs, profit, and outstanding amount. Payment and cost editors do not expose their own currency selector.

Switching currency requires confirmation. It changes only the currency marker on the order and its payment/cost entries; every numeric minor-unit value remains unchanged. Fly performs no exchange-rate conversion.

