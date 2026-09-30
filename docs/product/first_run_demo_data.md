# First-run Demo Data

Fly starts with an empty workspace by default. The first-run screen offers an unchecked **Add demo data (optional)** choice. Demo records are initialized only when the user explicitly selects it, all three user-data tables—Customers, Orders, and Tasks—are empty, and the database has no `demoSeedVersion` marker.

When selected on a fresh database, the demo pack contains realistic, editable foreign-trade examples:

- 8 customers across Philippines, UAE, Saudi Arabia, UK, Thailand, Vietnam, and Indonesia.
- Follow-up history, next actions, notes, contacts, levels, statuses, and soft-color tags.
- 6 orders spanning inquiry, confirmation, production, balance collection, shipped, and completed states.
- USD and RMB orders with single-currency payments/costs, products, factories, urgency, importance, and priority examples.
- 11 tasks: 3 today, 2 tomorrow, future work, and 1 overdue task, covering all four matrix quadrants.

All dates are calculated from the first-run day. Calendar and Matrix use the seeded Tasks as their existing single source of truth.

`AppSettings.demoSeedVersion` prevents reseeding after users edit or delete examples. Databases upgraded from an older Fly version receive a negative initialization marker, so existing installations—including empty legacy databases—are never seeded or overwritten. No production startup path deletes data, and no reset control is exposed in Settings.
