---
name: flutter-testing
description: Plan, write, run, and diagnose Flutter unit, widget, integration, and regression tests, including analyzer checks. Use for test coverage, bug regression, flaky tests, and verification strategy without changing unrelated product behavior.
---

# Flutter Testing

Select tests by risk and observable behavior, not by a coverage percentage alone.

## Shared working contract

- Inspect the existing project, local instructions, working-tree changes, and relevant implementation/tests before modifying code.
- Preserve architectural and design conventions unless a concrete requirement justifies a change. Explain significant decisions and tradeoffs; do not quietly migrate the app.
- Keep changes scoped. Do not rewrite unrelated code, upgrade the SDK wholesale, or add unnecessary dependencies. Prefer readable, maintainable production code over demos and speculative abstractions.
- Respect the requested mode: a review or diagnosis is read-only unless implementation is also requested. Explicit user constraints take precedence over this workflow.
- After code changes, run `dart format` on changed authored Dart files, `flutter analyze`, and relevant tests using the project's SDK, package root, flavors, and scripts. Use equivalent repository wrappers where configured.
- Fix errors introduced by the change before declaring completion. Separate pre-existing failures from regressions. If tooling, credentials, a device, or a host platform blocks a check, report exactly what was not verified; never claim a pass.
- Preserve user data, credentials, generated-file conventions, and unrelated work. Publishing, deployment, destructive resets, and production-data tests require appropriate explicit authorization.

## Inspect and select a strategy

Read pubspec/lockfile, SDK pinning, analysis options, test configuration, existing helpers, mocks/fakes, CI commands, native setup, and the relevant feature. Identify supported targets and available devices. Distinguish a source regression from infrastructure, version, or pre-existing failures.

Map acceptance criteria to the smallest reliable layer:

- Unit tests: business invariants, transformations, validation, serialization, financial/date calculations, state transitions, and repository policy.
- Widget tests: user-visible states, input, focus, accessibility semantics, responsive behavior, and navigation at Flutter level.
- Integration tests: critical cross-layer journeys, real persistence/restarts, native plugins, permissions, platform adapters, and device behavior that widget tests cannot establish.

Prefer a focused regression that fails for the reported bug before fixing it. Use existing tools; do not add a mocking or test framework solely for convenience.

## Unit and repository tests

- Cover normal, boundary, empty, malformed, failure, and relevant cancellation/concurrency cases. Assert outputs and invariants rather than internal private calls.
- Inject clocks, IDs, network clients, randomness, and persistence where needed. Make time-zone, midnight, and recurrence semantics explicit; use integer/decimal assertions for money rather than hiding errors behind loose tolerances.
- Use lightweight fakes for external dependencies and real isolated persistence when SQL, constraints, transactions, or migrations are what the test must prove.
- Test DTO/entity mapping and error translation at real boundaries. Do not mock away the operation under test.
- Use synthetic data and temporary databases/directories. Never point tests at a user's database or live production account.

## Widget tests

- Pump the real relevant widgets with controlled dependency overrides. Scope providers/routes and dispose owned resources consistently with production lifecycles.
- Find widgets by meaningful keys, semantics, or text that forms part of the contract. Avoid fragile tree positions and implementation-specific assertions.
- Exercise actions and assert resulting state: loading to data/error, retries, validation, double-submit prevention, empty states, selection, and navigation.
- Control time deliberately. Use bounded pumps for animations, debounce, and pending work; avoid blanket sleeps and unbounded pumpAndSettle with ongoing spinners.
- Use runAsync only for real asynchronous work that must escape fake time. Drain relevant queued work after disposal; do not suppress timer/leak assertions or patch production behavior to hide test cleanup defects.
- Restore view size, pixel ratio, locale, platform overrides, and other global test state. Dispose databases, containers, controllers, and subscriptions.
- Test meaningful phone/tablet sizes, text scaling, theme variants, and accessibility semantics for changed UI. Pin fonts/environment for golden tests and inspect diffs before updating baselines.

## Integration and platform checks

Use existing integration_test or repository harnesses. Select a known device/emulator and flavor; verify it is a safe environment before running a test that writes data. Keep credentials out of fixtures and logs.

Cover only the important end-to-end journeys at this costlier layer, including persistence/restart, routing, authentication state, or platform permissions when affected. Keep backend dependencies isolated or explicitly configured.

An Android pass does not validate iOS. A host-only test does not prove native plugin behavior. iOS build/device verification needs a suitable macOS/Xcode environment; explicitly list missing platform checks.

## Execute and diagnose

For code changes, run formatting and analysis plus tests, adapted to repository wrappers:

```text
dart format <changed-authored-dart-files>
flutter analyze
flutter test <focused-test-files>
flutter test
flutter test integration_test/<journey>_test.dart -d <available-device>
```

The full suite and device command are risk- and availability-dependent, not permission to run against production. Use package-scoped commands for monorepos and inspect affected dependents.

On failure, reproduce the smallest case, inspect the first meaningful error, and determine whether implementation, expectation, or infrastructure is wrong. Change assertions only when the intended contract changed. Do not make tests pass by skipping them, broadening tolerances without justification, swallowing errors, or blindly refreshing goldens.

Use retries diagnostically, not to disguise flakiness. Investigate order dependence, leaked resources, uncontrolled time/network, race conditions, and environment differences. Run broader regression coverage after shared routing, state, persistence, or dependency changes.

## Completion evidence

Report commands/checks actually run, pass/fail and scope, unresolved failures, unavailable devices, and any intentionally untested behavior. Do not infer success from starting a command or from partial output. Keep test artifacts/logs free of sensitive data and distinguish golden approval from behavioral correctness.
