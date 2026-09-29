# Routing

| Route | Purpose |
|---|---|
| `/customers/today` | Customers requiring follow-up today |
| `/customers/next7days` | Customers requiring follow-up in the next seven days |
| `/customers/inbox` | Customers without a follow-up date |
| `/customers/all` | All active customers |
| `/customers/category/:id` | Dynamic customer-category projection |
| `/customers/deleted` | Soft-deleted customers |
| `/orders/all` | All active orders, newest first |
| `/orders/important` | Important-order projection |
| `/orders/normal` | Normal-order projection |
| `/orders/tag/:id` | Order-tag projection |
| `/orders/deleted` | Soft-deleted orders |
| `/dashboard` | Default when Dashboard is visible |
| `/tasks/today` | Open tasks whose date interval intersects the local day; single-ended dates must be today |
| `/tasks/next7days` | Tasks in the next seven days |
| `/tasks/inbox` | Built-in Inbox |
| `/tasks/list/:id` | Custom list projection |
| `/tasks/completed` | Completed tasks |
| `/tasks/trash` | Soft-deleted tasks |
| `/calendar` | Month projection |
| `/matrix` | Importance/urgency projection |
| `/task/:id` | Addressable task detail |

A GoRouter `ShellRoute` keeps primary navigation around all modules. `PrimaryModule` is derived from the hierarchical route. Expanded Customer, Order, and Task routes show the primary rail, their own module sidebar, compact list, and selected detail. Calendar and Matrix show only the primary rail and their workspace. Compact windows use bottom navigation.

Customer → Orders navigation sets `orderCustomerFilterProvider` before routing to `/orders/all`; the filter is visible and dismissible. Order → Customer navigation sets the selected customer before routing to `/customers/all`.

Legacy task URLs redirect to their `/tasks/...` equivalents.

Polish V8 reads persisted navigation visibility before resolving cold startup: Dashboard, otherwise Customers Today when CRM is visible, otherwise Tasks Today. Customer and Order visibility is coupled. The same resolver guards hidden routes and redirects when the current module becomes hidden; hiding never removes business records. See `polish_v8.md`.

Unknown/deleted task IDs render a missing-task state instead of crashing.
