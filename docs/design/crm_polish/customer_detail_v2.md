# Customer Detail V2

## Goal

Keep the customer identity and current sales state readable in one viewport while moving long-lived history into an on-demand extension panel.

## Information order

1. Customer name and next action
2. Category / status
3. Source / priority
4. Next follow-up / recurrence
5. Tags
6. Latest note preview
7. Latest follow-up preview
8. Order summary and actions
9. Collapsed basic information and contacts

The source field is deliberately promoted out of Basic Information. Notes and follow-ups show only their latest record in the detail panel.

## Order actions

- `查看订单` opens Orders with the current customer filter.
- `新建订单` creates an order with the current customer, today's order date, and the existing automatic number strategy, then opens that new Order Detail.

Both actions are lightweight text/outline controls rather than primary filled buttons.
