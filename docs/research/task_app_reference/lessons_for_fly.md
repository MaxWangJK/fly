# Lessons for Fly

## Adopt as principles

1. One task identity feeds List, Calendar, Matrix, and detail projections.
2. Persist user intent locally before driving UI refresh.
3. Separate stable business IDs from database implementation details.
4. Treat completion, deletion, recurrence, reminder, and sync as distinct concerns.
5. Store sort order as domain data.
6. Keep the desktop shell stable and detail contextual.
7. Convert drag targets into explicit model updates.
8. Design indexes around active/list/date/matrix queries.
9. Isolate platform integration.
10. Keep future sync metadata possible without adding a server prematurely.

## Deliberately redesign

- Fly uses feature-first Flutter modules rather than mirroring WPF namespaces.
- Riverpod and Drift streams replace ViewModel notifier/cache plumbing.
- Fly's Matrix is explicitly calculated from independent `importance` and `urgency` booleans.
- Fly enforces foreign keys where practical.
- Fly has its own blue-gray visual system, spacing, typography, motion, and responsive breakpoints.
- V1 has no account, server, cloud sync, native reminder delivery, attachments, or collaboration.

## Stop condition

The reference is now sufficient. Fly runtime and tests do not load ReferenceApp binaries, databases, resources, or decompiled sources. Future implementation decisions should cite product requirements and Fly architecture, not depend on continued reverse engineering.
