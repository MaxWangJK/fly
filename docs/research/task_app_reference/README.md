# ReferenceApp Reference Research

This directory records architecture knowledge extracted from a static, local study of the installed ReferenceApp Windows client. It is a product-engineering reference, not a source dependency.

## Scope and boundary

The study covered application composition, UI structure, models, local persistence, state propagation, reminders, recurrence, calendar projections, synchronization boundaries, and build reconstruction. It explicitly excluded licensing, authentication bypass, paid-state manipulation, and server access-control research.

No decompiled C# source, binaries, database rows, resources, logos, or proprietary assets are included in Fly. Schema inspection of the local database was read-only and limited to metadata such as tables, columns, and indexes.

## Result

The evidence is sufficient to stop researching ReferenceApp and develop Fly independently. Build reconstruction is rated **B: core assemblies can build**. The durable outcome is this set of diagrams, relationships, state flows, and design lessons.

## Document map

- Architecture: `architecture.md`, `dependency_graph.md`, `startup_flow.md`
- UI: `ui_architecture.md`, `navigation_architecture.md`, `view_viewmodel_mapping.md`
- Domain: `task_model.md`, `task_state_machine.md`, `calendar_model.md`, `recurrence_model.md`, `reminder_model.md`
- Persistence and state: `database_schema.md`, `database_er_diagram.md`, `state_management.md`, `sync_architecture.md`
- Evaluation: `interaction_patterns.md`, `build_reconstruction.md`, `lessons_for_fly.md`

## Portable document normalization

Brand names and original machine-specific identifiers were neutralized on 2026-10-14. `ReferenceApp` is an explanatory placeholder; reconstruction paths and identifiers are historical structure examples, not runnable Fly build inputs.
