# Startup Flow

```mermaid
sequenceDiagram
  participant OS
  participant App
  participant Storage
  participant Services
  participant UI
  OS->>App: Launch
  App->>App: Acquire single-instance mutex
  App->>Storage: Resolve application-data paths
  App->>App: Start safely / recover settings
  App->>Storage: Open database, enable WAL, ensure schema/indexes
  App->>Services: Initialize local settings, theme, language
  App->>Services: Initialize task/calendar libraries
  App->>UI: Choose login/main window path
  App->>Services: Start reminder, time/date/timezone observers
  App->>Services: Start pipe, widgets and tray integrations
  App->>UI: Enter WPF event loop
```

The installed client resolves data under the user's application-data area and uses a single-instance guard. Database readiness precedes the main experience. Background concerns are initialized after foundational configuration.

## Lessons

Startup should have a small ordered bootstrap with visible failure boundaries. Fly V1 keeps it shorter: initialize Flutter, open Drift, run schema setup, create the built-in Inbox, optionally seed debug data, then mount Riverpod and the router. No login or network gates exist.
