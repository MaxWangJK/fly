# ADR-004: Shared Tag Engine, Separate Application Links

## Decision

Reuse the existing `tags` table for names and soft colors. Add `customer_tag_links` and `order_tag_links`; retain `task_tags`.

## Rationale

Names such as 菲律宾, WPC, and 急单 benefit from one searchable color vocabulary, while the three aggregates need independent membership and filtering. Separate link tables prevent Customer, Order, and Task lifecycle coupling.

Customer categories hold an optional linked tag ID. Category creation creates or reuses a tag; category rename updates the linked tag in the same transaction. Deactivation leaves the tag and historical links intact.

## Consequences

- Tag rename/color changes are shared intentionally.
- Tag application queries remain aggregate-specific.
- Deleting an application link never deletes the shared tag.
- Tag-name uniqueness remains global and case-normalized in repository validation.
