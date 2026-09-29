# Database Migration Plan V2

Schema version increases from 1 to 2. Migration is additive: no existing Task, Calendar, Matrix, list, reminder, checklist, or tag table is dropped, rewritten, or cleared.

## New tables

```text
customers
customer_categories
customer_statuses
customer_sources
customer_contacts
customer_follow_ups
customer_tag_links

orders
order_statuses
order_production_items
order_payments
order_tag_links
order_files
factories
products
```

The existing `tags` table is reused as the shared tag engine. Customer and Order applications remain separate through `customer_tag_links` and `order_tag_links`.

## Upgrade transaction

For `from < 2`, Drift creates only the new tables and indexes. Foreign keys use cascade only for true aggregate children. `orders.customer_id` is nullable so an order remains readable when a customer is soft-deleted. Roots use `deleted_at`; repositories never physically delete Customer or Order records.

Default categories, customer statuses, customer sources, and order statuses are inserted with stable IDs using insert-if-absent semantics. Startup never overwrites renamed, recolored, reordered, or deactivated configuration.

## Indexes

- Customer active/due, category/sort, normalized Email/WhatsApp/Phone.
- Follow-up customer/date.
- Order active/created, customer/created, status/created.
- Production item order/factory status.
- Payment order/date and file order/document type.
- Customer and Order tag-link reverse indexes.

Migration tests open a schema-v1 database, insert an existing Task, run schema-v2 migration, and verify the Task remains unchanged while new CRM/Order tables are available.
