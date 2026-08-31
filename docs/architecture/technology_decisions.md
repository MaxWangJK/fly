# Technology Decisions

## Flutter

**Why:** one UI/domain codebase can target Windows now and macOS, Android and iOS later. Flutter gives consistent custom desktop layouts and mature testing.

**Trade-off:** desktop conventions and installer integration require deliberate work; binary size is larger than a native WPF-only client.

**Alternatives:** WPF would optimize only Windows; Electron would use web skills but with a heavier runtime. Flutter best matches the four-platform direction.

## Riverpod

**Why:** compile-visible providers, explicit dependency injection, reactive composition and straightforward test overrides.

**Trade-off:** provider lifecycle and family keys require discipline. A plain ChangeNotifier stack would be smaller initially but makes query/dependency growth harder.

## Drift and SQLite

**Why:** SQLite is durable, transactional, offline and portable. Drift supplies typed queries, migrations, streams and testable in-memory executors.

**Trade-off:** generated code is large and schema migration design remains the team's responsibility. Plain sqflite would reduce generation but lose typed reactive queries.

## GoRouter

**Why:** stable addressable routes support shell navigation, deep-link foundations and compact task-detail navigation.

**Trade-off:** nested shell behavior is more formal than manual Navigator calls, but avoids global page booleans.

## Local first

**Why:** V1 remains fully useful offline, avoids account/server scope and makes SQLite the unambiguous source of truth.

**Trade-off:** multi-device access and collaboration are absent. Future sync must be designed explicitly, not added as silent background magic.

## UUID business IDs

**Why:** IDs can be created offline and remain stable across export, future devices, or synchronization.

**Trade-off:** strings occupy more index space than integer row IDs. The portability benefit outweighs this for personal task volumes.

## No Freezed in V1

The domain is small enough for explicit immutable classes and `copyWith`. Avoiding another generator reduces dependencies; revisit if union types or model volume materially grow.
