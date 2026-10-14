---
name: flutter-architecture
description: Design, review, or refactor Flutter feature boundaries, Riverpod state, repositories, data sources, dependency injection, and GoRouter flows. Use when a request involves architectural decisions; do not impose an architecture migration for ordinary widget edits.
---

# Flutter Architecture

Choose the smallest architecture that provides clear ownership, testable boundaries, and safe evolution.

## Shared working contract

- Inspect the existing project, local instructions, working-tree changes, and relevant implementation/tests before modifying code.
- Preserve architectural and design conventions unless a concrete requirement justifies a change. Explain significant decisions and tradeoffs; do not quietly migrate the app.
- Keep changes scoped. Do not rewrite unrelated code, upgrade the SDK wholesale, or add unnecessary dependencies. Prefer readable, maintainable production code over demos and speculative abstractions.
- Respect the requested mode: a review or diagnosis is read-only unless implementation is also requested. Explicit user constraints take precedence over this workflow.
- After code changes, run `dart format` on changed authored Dart files, `flutter analyze`, and relevant tests using the project's SDK, package root, flavors, and scripts. Use equivalent repository wrappers where configured.
- Fix errors introduced by the change before declaring completion. Separate pre-existing failures from regressions. If tooling, credentials, a device, or a host platform blocks a check, report exactly what was not verified; never claim a pass.
- Preserve user data, credentials, generated-file conventions, and unrelated work. Publishing, deployment, destructive resets, and production-data tests require appropriate explicit authorization.

## Establish the current shape

Inspect SDK and package versions, pubspec and analyzer configuration, feature directories, composition roots, providers, routing, repositories, persistence, and tests. Trace one relevant path from screen intent through state to data and back.

Identify where the current design causes a concrete problem: duplicated policy, hidden dependencies, lifecycle leaks, inconsistent state, transport types in UI, or untestable side effects. Preserve a working Bloc, Provider, MVC, or other architecture unless migration is explicitly justified.

## Clean Architecture, proportionate to the feature

Use inward dependencies: presentation depends on application/domain contracts; data implementations satisfy those contracts. Domain rules should not require widgets, HTTP clients, plugin calls, or database-generated rows.

A useful feature-oriented shape, only where it fits the repository:

```text
lib/
  app/                         # composition, routing, app-level concerns
  features/<feature>/
    presentation/              # screens, reusable feature widgets, state
    domain/                    # entities, invariants, repository contracts
    data/                      # repository implementations, DTOs, data sources
  shared/                      # genuinely cross-feature capabilities
```

Keep names and layering consistent with local conventions. Add an application/use-case layer when orchestration or reusable policy warrants it; do not generate a use-case class for every trivial getter. Promote code to shared only when there is real cross-feature ownership.

## Entities, DTOs, repositories, services

- Entities express business identity, invariants, and typed values. DTOs represent external schemas; persistence records and transport DTOs are not automatically domain entities.
- Map across a boundary when external nullability, naming, schema evolution, or invariants differ. Avoid ceremonial duplicate classes when representations genuinely coincide.
- Define repository contracts around business operations. Decide where caching, local/remote reconciliation, transactions, and error mapping belong; do not scatter them across screens.
- Data sources own concrete I/O. Platform services/adapters own device and plugin access. A service should have an identifiable responsibility, not become a catch-all dependency.
- Handle money, dates, time zones, identifiers, and serialization with explicit semantics appropriate to the existing domain.
- Preserve data compatibility with additive, tested migrations where needed. Never replace a database to simplify a refactor.

## Riverpod and dependency injection

When Riverpod is already used or explicitly selected:

- Follow the installed version and local generated-versus-manual provider convention. Do not introduce code generation or change provider APIs merely to match a newer tutorial.
- Define dependencies at the composition boundary. Inject repositories/services through providers or constructors rather than instantiating I/O in widgets or using global mutable singletons.
- Keep ephemeral UI state local where appropriate. Let feature state coordinate user actions; let repositories/services own business and I/O policy.
- Represent asynchronous states explicitly, including refresh and failure behavior. Prevent stale responses from replacing newer results; scope keyed state to stable immutable arguments.
- Use reactive watching for render dependencies and imperative reads for actions where appropriate. Avoid side effects inside build and broad rebuild subscriptions.
- Choose provider lifetime deliberately. Dispose owned resources, scope authentication/user-specific state correctly, and invalidate affected caches after mutations or account changes.
- Override dependencies in tests without production backdoors. Do not weaken production initialization to accommodate tests.

## GoRouter

When GoRouter is present or explicitly chosen:

- Keep route ownership and typed/validated parameters clear. Preserve deep links, browser history where supported, back behavior, and existing shell/nested navigation semantics.
- Centralize authentication, onboarding, and visibility redirects. Model loading explicitly; prevent redirect loops and inaccessible current routes.
- Keep the router instance stable across ordinary state rebuilds; use the installed version's supported refresh mechanism and dispose resources.
- Decide deliberately what belongs in route state versus selected UI state. Keep cross-feature navigation from coupling one feature's data implementation to another's widgets.
- Test cold starts, restored state if supported, deep links, missing/deleted IDs, and permission/visibility changes.

## Decisions and verification

For a significant change, give a brief decision record: problem, constraints, options, chosen boundaries, consequences, and migration/rollback strategy where applicable. Use existing ADR conventions; do not require a new document for a tiny edit.

Test domain invariants, mapping, repository contracts, provider transitions/lifecycles, and routing guards as affected. Run `dart format`, `flutter analyze`, and relevant tests for implemented changes. For a read-only review, provide evidence and a scoped recommendation without silently implementing it.
