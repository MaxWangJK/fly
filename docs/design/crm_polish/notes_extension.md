# Notes Extension

Customer notes are independent `CustomerNote` records, not Markdown stored only on Customer.

The detail panel queries and displays only the latest note. Clicking the preview opens one right extension panel containing:

- live content search;
- one 2–4 line input focused on open;
- Enter to create and Shift+Enter for a line break;
- newest-first soft-color blocks;
- relative creation time and edited state;
- edit by double-click or menu;
- soft delete;
- batches of 20 with Load More.

Colors rotate through low-saturation blue, yellow, green, purple, and gray. A successful create clears the input, keeps focus, and inserts the block at the top without a redundant Snackbar.

Schema v3 copies every non-empty legacy `customers.notes` value to a CustomerNote while retaining the old field for compatibility.
