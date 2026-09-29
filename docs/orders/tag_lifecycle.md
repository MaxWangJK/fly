# Order Tag Lifecycle

Tags use the shared Tag engine and have an `isActive` lifecycle flag.

- Active tags appear in the order sidebar and new-tag selector.
- The sidebar shows at most eight active tags, ranked by current order usage and stable creation order.
- Disabling a tag keeps all customer/order/task links and history, but hides it from active navigation and selection.
- The management dialog can include inactive tags and re-enable them.
- Rename updates the shared definition.
- Deleting a regular tag is transactional and removes its customer, order, and task links before deleting the definition.
- Category-linked tags are protected and must be managed through Customer Category.
