# CRM Filter Semantics

Customer categories and tags remain separate data concepts, but they share one predictable filter experience.

- A category route matches a customer when `customer.categoryId` is the selected category **or** the customer explicitly owns that category's linked tag.
- A normal tag matches through `customer_tag_links`.
- Multiple selected tags use AND. For every selected category-linked tag, either the customer's category or an explicit tag link satisfies that term.
- Selecting a category in the sidebar clears earlier filters and selects exactly its linked tag. Selecting “全部客户” clears filters.
- Category changes synchronize the automatic category tag transactionally. Manually assigned tags remain intact.

This lets a customer categorized as B级 but explicitly tagged A级 appear under both useful projections without collapsing Category and Tag into one domain.
