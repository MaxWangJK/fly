# State Management

## Durable state

Drift/SQLite owns tasks, lists, tags, task-tag links, checklist items and reminders. Repository streams are the only path from durable records to UI projections.

## Application state

Riverpod owns:

- selected task ID
- selected calendar date
- visible calendar month
- theme mode
- query subscriptions for Inbox, Today, Upcoming, list, range, task, tags, checklist and reminder

Application state may disappear when the process exits. Durable task state may not.

## Mutation rule

A widget invokes a repository command. It does not edit a cached list and later attempt to reconcile. After the SQLite write, Drift invalidates relevant queries and Riverpod rebuilds subscribed widgets.
