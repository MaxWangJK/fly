---
name: flutter-development
description: Implement and maintain Flutter apps and Dart packages, including scoped features, bug fixes, SDK-aware dependencies, and platform compatibility. Use for general Flutter development; for architecture-only, UI-only, or test-only work, prefer the corresponding focused skill.
---

# Flutter Development

Deliver a working, verified change within the existing app, not a replacement project.

## Shared working contract

- Inspect the existing project, local instructions, working-tree changes, and relevant implementation/tests before modifying code.
- Preserve architectural and design conventions unless a concrete requirement justifies a change. Explain significant decisions and tradeoffs; do not quietly migrate the app.
- Keep changes scoped. Do not rewrite unrelated code, upgrade the SDK wholesale, or add unnecessary dependencies. Prefer readable, maintainable production code over demos and speculative abstractions.
- Respect the requested mode: a review or diagnosis is read-only unless implementation is also requested. Explicit user constraints take precedence over this workflow.
- After code changes, run `dart format` on changed authored Dart files, `flutter analyze`, and relevant tests using the project's SDK, package root, flavors, and scripts. Use equivalent repository wrappers where configured.
- Fix errors introduced by the change before declaring completion. Separate pre-existing failures from regressions. If tooling, credentials, a device, or a host platform blocks a check, report exactly what was not verified; never claim a pass.
- Preserve user data, credentials, generated-file conventions, and unrelated work. Publishing, deployment, destructive resets, and production-data tests require appropriate explicit authorization.

## Inspect and plan

1. Read repository instructions, `pubspec.yaml`, `pubspec.lock` when present, `analysis_options.yaml`, SDK pinning (such as FVM), and CI/build scripts. In a monorepo, identify the owning package and affected dependents.
2. Locate the relevant feature, state management, repositories, routes, widgets, generated code, and tests. Read a comparable feature before choosing a pattern.
3. Identify supported platforms from source and configuration, not just the current host. Check Flutter/Dart versions with the configured SDK. If PATH is stale, resolve the repository or user-provided SDK rather than changing machine-wide configuration.
4. Turn the request into observable acceptance criteria. For a bug, reproduce it or add a failing regression test where practical. Note baseline analyzer/test failures when relevant.
5. Explain the implementation approach briefly. Ask only when an unresolved choice materially changes scope, behavior, compatibility, or data safety.

## Implement

- Keep business rules out of widget build methods. Follow existing state-management and error-handling conventions; separate recoverable failures from programming errors.
- Use sound null safety and typed APIs. Prefer immutable values and explicit updates. Avoid unchecked casts, broad `dynamic`, force-unwrapping, and swallowed exceptions.
- Keep build methods free of side effects. Dispose owned controllers, subscriptions, timers, and focus nodes. Check lifecycle validity before using UI context after asynchronous work.
- Model loading, failure, empty, success, cancellation, and retry where the interaction needs them. Avoid duplicate submissions and stale asynchronous results.
- Reuse existing localization, theme tokens, platform adapters, persistence, and logging. Do not embed secrets, real customer data, or environment-specific paths in reusable code.
- Update generated outputs only through the project's generator workflow. Preserve compatibility and migration paths for serialized or persisted models.
- Build in small coherent increments; exercise the changed behavior before expanding the patch.

## Dependencies and pubspec

Prefer existing packages, the Dart SDK, and Flutter APIs. Add a dependency only for a concrete capability whose benefit outweighs maintenance and compatibility costs. Inspect its SDK constraints, platform support, license, transitive impact, and native setup using documentation appropriate to the resolved version.

Make targeted `pubspec.yaml` changes. Run `flutter pub get` when dependency, asset, or localization configuration changes; inspect the lockfile diff. Follow repository lockfile policy for apps versus reusable packages. Do not use broad upgrades, dependency overrides, cache deletion, or `flutter clean` as routine fixes.

Do not copy API examples from a different major version. Consult installed sources or official Flutter, Dart, and package documentation when behavior is uncertain.

## Android and iOS compatibility

- Inspect Android manifests, Gradle/Kotlin/Java settings and minimum SDK, and iOS deployment targets, Info.plist, entitlements, and CocoaPods/SPM configuration when affected.
- For plugins, verify permissions, usage descriptions, native setup, runtime denial behavior, and support on every declared target. Avoid unsupported imports crossing platform boundaries.
- Account for touch/keyboard input, safe areas, text scaling, orientation, lifecycle changes, and back navigation.
- Keep desktop/web support intact if the project declares it; do not add missing target platforms without a requirement.
- Native iOS builds require a suitable macOS/Xcode environment. Report that limitation on Windows/Linux instead of treating Android or widget tests as iOS validation.
- Build and run affected target(s) when requested or warranted by native changes, using development credentials and safe test data. Do not sign or publish releases implicitly.

## Verify and hand off

Run changed-file formatting, full analyzer, focused tests, and broader regression tests proportional to the affected surface. Use repository CI commands when they add required checks. Review the final diff for unrelated edits, generated artifacts, and dependency churn.

Report changed behavior, important decisions, checks actually run with results, and any remaining limitations. Do not call a change production-ready solely because it compiles.
