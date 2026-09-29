# Financial panel

The main detail shows only sales amount, estimated profit, and outstanding amount. Editing lives in the financial extension and follows business order rather than table order:

1. Income — sales amount and sales currency;
2. Payments — deposit sum, balance-payment sum, total received, and outstanding;
3. Costs and fees — factory cost, inland cost, port charges, and other cost;
4. Tax — tax refund;
5. Result — estimated profit and margin.

Deposit and balance figures are derived from `OrderPayment` rows by payment type. They are not duplicated as stored totals. Received and outstanding include only payments in the order sales currency; mismatched payment currency is visibly excluded from arithmetic.

Profit uses `baseProfitCurrency`. When the sales currency matches the base currency, the conversion factor is one. For cross-currency orders, `exchangeRateMicros` represents one unit of sales currency in the base currency. Without a positive rate, profit and margin are unavailable and the UI asks for the rate instead of subtracting unlike currencies.

The formula is:

`profit = converted sales - factory cost - inland cost - port charges - other cost + tax refund + other income`

All monetary values remain integer minor units. Profit is computed, not treated as a second source of truth.

