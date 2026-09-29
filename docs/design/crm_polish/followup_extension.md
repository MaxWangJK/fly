# Follow-up Extension

Follow-ups remain a separate CustomerFollowUp domain. The customer detail displays only the latest content, channel, and relative time.

The shared right extension framework provides:

- content/channel search;
- one main input;
- a small progressive channel menu;
- Enter to create and Shift+Enter for a line break;
- newest-first history blocks;
- batches of 20 with Load More.

Creating a record updates `followedUpAt` and Customer `lastFollowUpAt`. It does not clear or change `nextFollowUpDate` unless the recurrence completion flow explicitly supplies a new date. Existing optional `nextAction` data remains visible on historical blocks.
