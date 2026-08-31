# Routing

| Route | Purpose |
|---|---|
| `/today` | Tasks due today |
| `/inbox` | Built-in Inbox |
| `/upcoming` | Tasks after today |
| `/calendar` | Month projection |
| `/matrix` | Importance/urgency projection |
| `/list/:id` | Custom list projection |
| `/task/:id` | Addressable task detail |

A GoRouter `ShellRoute` keeps navigation around collection views. Expanded windows show selected detail beside content. Medium uses a navigation rail. Compact uses bottom navigation and the addressable task page.

Unknown/deleted task IDs render a missing-task state instead of crashing.
