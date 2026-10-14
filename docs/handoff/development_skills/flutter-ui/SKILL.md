---
name: flutter-ui
description: Build and refine Flutter screens and reusable widgets with responsive phone/tablet layouts, themes, accessible interactions, and complete UI states. Use for Flutter visual or interaction work, preserving the existing design system.
---

# Flutter UI

Deliver usable, accessible interfaces that fit the app's established visual language.

## Shared working contract

- Inspect the existing project, local instructions, working-tree changes, and relevant implementation/tests before modifying code.
- Preserve architectural and design conventions unless a concrete requirement justifies a change. Explain significant decisions and tradeoffs; do not quietly migrate the app.
- Keep changes scoped. Do not rewrite unrelated code, upgrade the SDK wholesale, or add unnecessary dependencies. Prefer readable, maintainable production code over demos and speculative abstractions.
- Respect the requested mode: a review or diagnosis is read-only unless implementation is also requested. Explicit user constraints take precedence over this workflow.
- After code changes, run `dart format` on changed authored Dart files, `flutter analyze`, and relevant tests using the project's SDK, package root, flavors, and scripts. Use equivalent repository wrappers where configured.
- Fix errors introduced by the change before declaring completion. Separate pre-existing failures from regressions. If tooling, credentials, a device, or a host platform blocks a check, report exactly what was not verified; never claim a pass.
- Preserve user data, credentials, generated-file conventions, and unrelated work. Publishing, deployment, destructive resets, and production-data tests require appropriate explicit authorization.

## Inspect the interaction and design system

Read the relevant screens, shared widgets, theme extensions/tokens, localization, routes, state, and tests. Inspect pubspec/SDK constraints before choosing APIs. Establish the intended user action, target form factors, and acceptance states; use supplied screenshots as references, not as permission to rebuild unrelated screens.

Use Material 3 components and color/text schemes when compatible with the current app. Do not globally enable Material 3 or restyle a Cupertino/custom design system just to implement one screen.

## Structure and responsiveness

- Extract reusable widgets around repeated behavior or stable design concepts. Give them small, typed APIs; avoid giant configuration objects and arbitrary variants.
- Keep layout/presentation separate from business side effects. Connect state at deliberate boundaries so reusable visual widgets can be tested independently.
- Use parent constraints (for example LayoutBuilder) for local layout decisions and MediaQuery for window/environment information. Choose breakpoints from content needs and established tokens, not device-name assumptions.
- Phone layouts should support constrained width, safe areas, the on-screen keyboard, scrolling, orientation, and touch. Tablet layouts may introduce panes or wider navigation while preserving selection and navigation context.
- Preserve desktop/web adaptation when declared by the project: resizing, focus, keyboard commands, pointer behavior, and hover must complement touch rather than replace it.
- Avoid fixed heights for variable-length text and fixed widths that cause overflow. Handle long localized labels, text scaling, RTL when supported, and empty or unusually large data sets.
- Use lazy collections where appropriate. Preserve scroll position and stable keys; do not hide content with clipping or shrink text indiscriminately to conceal layout defects.

## Theme and typography

Use existing ColorScheme, TextTheme, theme extensions, spacing, shape, and elevation tokens. Let surfaces and controls adapt to light/dark themes; do not scatter hardcoded colors. Reserve local colors for semantic needs, with appropriate contrast in both modes.

Keep a clear title/body/metadata hierarchy. Use the app's font fallback and localization conventions. Secondary information must remain readable rather than simply becoming tiny or low-contrast. Do not encode status through color alone.

## States, input, and animation

Design loading, empty, populated, error/retry, disabled, submitting, and success states where applicable. Keep refresh distinct from first load so content need not disappear. Avoid layout jumps and duplicate submissions.

Provide clear validation, focus progression, keyboard dismissal, and recoverable errors. Preserve entered text across recoverable failures. Follow existing confirmation/undo behavior for destructive actions.

Use animations to explain state or spatial transitions, not to delay work. Respect reduced-motion settings and current SDK support. Dispose animation controllers and avoid rebuilding large subtrees for local motion. Check performance on representative devices when animation complexity warrants it.

## Accessibility

- Supply meaningful semantics and labels for icon-only or custom controls. Expose selected, checked, disabled, and expanded state correctly; avoid duplicate announcements.
- Preserve platform-appropriate tap targets, visible focus, logical traversal, keyboard activation, and back navigation.
- Check text contrast, text scaling, and meaning without color. Ensure errors identify the affected field and how to recover.
- Verify with accessibility guideline/widget tests where available. Use TalkBack/VoiceOver on appropriate devices when the task warrants it; disclose if unavailable.
- Ensure overlays, dialogs, and sheets are reachable, dismissible where appropriate, and do not trap focus unintentionally.

## Verify visually and behaviorally

Exercise representative phone and tablet constraints, light/dark mode, large text, keyboard-visible forms, long content, and failure/empty states relevant to the change. Use actual rendered screenshots or the running app, not only source inspection; keep demo data isolated from real user data.

Add widget tests for behavior and semantics. Use golden tests only with the repository's controlled fonts/platform/baselines; review visual changes before accepting a new baseline. For native interactions, use device integration checks where available.

Run `dart format`, `flutter analyze`, and relevant tests. Report what was visually inspected and on which sizes/platforms, plus unverified device or accessibility checks.
