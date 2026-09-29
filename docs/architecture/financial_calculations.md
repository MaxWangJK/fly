# Order Financial Calculation Plan

All monetary values are signed 64-bit integers in the currency's minor unit. USD 20,000.00 is stored as `2_000_000`. UI formatting and parsing are presentation concerns.

The order stores sales amount and non-factory adjustments. Factory cost is summed from production items. Payment totals are summed from payment records.

```text
factoryCost = SUM(orderProductionItems.factoryCost)

profit = salesAmount
       - factoryCost
       - inlandCost
       - portCharges
       - otherCost
       + taxRefund
       + otherIncome

profitMargin = salesAmount == 0 ? null : profit / salesAmount

receivedAmount = SUM(orderPayments.amount)
outstandingAmount = salesAmount - receivedAmount
isFullyPaid = outstandingAmount <= 0
```

`profit`, `profitMargin`, `receivedAmount`, `outstandingAmount`, and `isFullyPaid` are computed read-model values and are not duplicated as authoritative database columns.

Receiving full payment shows a lightweight suggestion to move to the configured “已收尾款” status; it never changes status automatically.
