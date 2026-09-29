# Customer ↔ Order Navigation Plan

Navigation state is explicit Riverpod state, not encoded into Task state.

```text
Customer Detail
  └─ View Orders
       ├─ set orderCustomerFilter = customer.id
       ├─ clear selectedOrderId
       └─ go /orders/all

Order Detail
  └─ Customer name
       ├─ set selectedCustomerId = order.customerId
       ├─ clear selectedOrderId
       └─ go /customers/inbox
```

Orders displays a removable customer filter chip. Removing it restores All Orders. Customer selection survives the module transition so returning from an Order opens the correct Customer detail immediately.

Primary module defaults:

```text
/customers/today
/orders/all
/tasks/today
/calendar
/matrix
```

No dialog is used for either root detail. Expanded Windows layout preserves Rail + Sidebar + List + Detail.
