# CRM / Orders Architecture V2

## Bounded contexts

`Customer`, `Order`, and `Task` are independent aggregates. They do not share persistence rows or lifecycle state. They may reuse value semantics such as priority, importance, urgency, recurrence, tags, soft deletion, sort order, and date handling.

```text
Customer aggregate                    Order aggregate
Customer                              Order
├─ CustomerCategory                   ├─ OrderStatus
├─ CustomerStatus                     ├─ OrderProductionItem
├─ CustomerSource                     ├─ OrderPayment
├─ CustomerContact                    ├─ OrderFile
├─ CustomerFollowUp                   ├─ Factory
├─ CustomerTagLink                    ├─ Product
└─ Order summaries (read model)       └─ OrderTagLink
```

The presentation layer keeps Fly's established four-region desktop shell:

```text
Primary Rail | Module Sidebar | Compact List | Context Detail
```

CRM routes own customer projections. Order routes own order projections. Riverpod providers expose reactive read models and explicit commands; widgets never issue SQL directly.

## CRM behavior

- Today includes customers due or overdue today and customers already followed up today. Completed follow-ups sort last without completing the customer.
- Completing today's follow-up inserts a `CustomerFollowUp`, updates `lastFollowUpAt`, and advances `nextFollowUpDate` from today or the current scheduled date.
- Categories, statuses, and sources are dynamic records. Category rename and its linked shared tag rename occur in one transaction.
- Duplicate detection uses normalized Email, WhatsApp, and Phone values and warns without blocking creation or edits.
- Search and AND-tag filtering are read-model operations over active customers.

## Orders behavior

- Order sidebar items are projections (`all`, `important`, `normal`, tag), never separate tables.
- Factory and Product are reusable lightweight entities. Production items reference both and retain their own commercial and execution state.
- Payments and files are appendable child records. Received, outstanding, factory cost, profit, and margin are computed read-model values.
- Soft deletion applies to Customer and Order roots. Child history remains durable; existing Orders survive Customer soft deletion.

## Progressive disclosure

Customer detail opens identity, category, status, next follow-up, recurrence, priority, tags, latest action, follow-up history, notes, and order summary. Contact channels and address fields live in a collapsed Basic Information section.

Order detail opens order number, customer, status, execution warning, production items, payment summary, and financial summary. Detailed costs, files, and notes use compact expandable sections.

## Deferred optional checklist

An order checklist can later be added as an aggregate child with user-defined rows and sort order. V2 deliberately does not encode PI, deposit, factory order, production, balance, booking, customs, or shipment as mandatory fixed steps because the core order status and factory-order state already cover the current acceptance scope.
