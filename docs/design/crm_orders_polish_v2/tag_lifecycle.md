# Tag lifecycle

Tags are shared definitions with separate customer, order, and task link tables. A tag link change is saved first, then the garbage collector evaluates only the removed candidate tags.

An ordinary tag is physically deleted only when all of these are true:

- no active customer references;
- no active order references;
- no active task references;
- no active customer category owns the tag.

Cleanup runs after customer tag changes, order tag changes, customer soft deletion, and order soft deletion. Customer and order rows remain soft-deleted; only a proven-unused ordinary tag definition is physically collected.

Category-linked tags are protected even when their current customer reference count is zero. Renaming a category continues to update the same tag instead of replacing it.

