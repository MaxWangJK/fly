# Fly Polish V10 — execution checkpoint

Source: user attachment 8efc1db8-b4ae-4958-a25b-0f7de7da2777 (full V10 request).
Status: in development, not final acceptance. Preserve all data and existing modules.

## 2026-09-22 continuation: build 16 localization closure work

- Release compiled successfully (101.2s); installer generated successfully
  (13.219s): dist/Fly-V10-Preview-20260922-build16.exe. Build 1.0.10+16.

- Completed container dynamic capacity/review/utilization/copy-summary text.
- Added presentation-only service error translation with exact known messages,
  parameter-preserving prefixes and unmodified unknown platform diagnostics.
- Applied errors to Files, Notes, import, backups, CRM, Orders and Settings.
- All three business notification types now use the persisted locale independently
  of the daily-review reminder toggle; scheduling/deduplication unchanged.
- Localized primary/compact navigation, empty detail panes, Dashboard and search
  controls/system result descriptions without rewriting business content.
- No automated tests/analyzer, installation or live application startup.
- Manual checklist: docs/release/v10-20260922-build16-manual-testing.md.
- This is not final acceptance or a claim that every native/visual path passed.

## 2026-09-21 continuation: build 15 export and dynamic CRM copy

- Export translation is injected into the workbook service, keeping Flutter UI
  context out of the data layer and preserving stored values/numbers.
- English customer templates and status/source header aliases added. Existing
  callers retain Chinese defaults; English examples are generated only on request.
- Dynamic deletion/duplicate/load-error copy, order summaries, note edited labels
  and attachment category display translated without changing persisted keys.
- Export failures now show a recoverable message rather than an unhandled future.
- Manual supplement: docs/release/v10-20260921-build15-manual-testing.md.
- Windows Release compilation succeeded (137.9s); installer generation succeeded
  (12.968s): dist/Fly-V10-Preview-20260921-build15.exe, 1.0.10+15 with local licensing.
  No analyzer, tests, installation or business app startup performed.
  Full i18n remains unfinished. Inno again reports Non-commercial use only.

## 2026-09-21 continuation: localization and exact media insertion

- Integrated the previous un-packaged settings/CRM/Orders localization work,
  relative-date presentation and ID-targeted slash media import.
- Localized container editing controls, context menu and generated space names
  in presentation only; stored names and packing rules remain untouched.
- Localized customer import wizard and export entry points. Picker returns now
  check that the dialog/context remains mounted before updating state.
- Installer custom prompts follow the chosen installer language.
- Intended build: 1.0.10+14. No automatic tests/analyzer or app startup requested.
  Release compilation succeeded (198.8s); Inno packaging succeeded (14.953s).
  Artifact: dist/Fly-V10-Preview-20260921.exe. No installation/app startup run.
- Manual checklist and remaining gaps: docs/release/v10-20260921-manual-testing.md.
  Full i18n remains unfinished; earlier checkpoint entries below are historical.

## 2026-09-13 continuation: manual cargo and offline trial

- 3D staging uses null section IDs, excludes staged cargo from loaded counts/weight,
  and persists manual cross-section placement. Only changed sections switch to
  manual mode; canceled previews do not commit. Section totals use actual groups.
- Add a single package directly to staging, including oversize cargo. Manual
  sections send new cargo to staging instead of silently replacing positions.
  Overflow confirmation displays X/Y/Z excess and preserves dimensions.
- New modular Ed25519 license service, Windows DPAPI registry adapter, 72h trial,
  persisted UTC high-water mark, copy-machine/activation gate. Private issuer key
  generated internally, never placed under Release/assets. See
  `docs/licenses/local_license_v10.md` for issuer usage and explicit limitations.
- Note right-click menu, Notes/Files workspace strings, block actions and shared
  folder tree now use localization. Full CRM/Orders/Settings/Tools localization
  and exact-position slash media insertion remain unfinished.
- User requested no automatic tests/analyzer. Formatting and Release builds only;
  activation, native drag, screenshots and business database checks not performed.
  Manual checklist: `docs/release/v10-trial-20260913-manual-testing.md`.
- Latest source compiled successfully as Windows Release 1.0.10+12 (86.1s),
  with ENABLE_LOCAL_LICENSE=true and the internal issuer's public key. Installer
  completed in 14.079s: `dist/Fly-V10-Trial-Preview-20260913.exe`.
  No installer execution or application launch was performed. Old packages remain.

## Required order

1. Task date ranges, Calendar intersections, Today/Overdue, postponement — implemented, focused tests pass.
2. Task context menu reduction — implemented, priority/list editing remains in details.
3. Matrix checkbox/title/time alignment — implemented, geometry test passes.
4. CRM context category, normalized unique names, free-text source, basic-info expansion — implemented, focused tests pass.
5. Global search — permanent rail entry and readable note block content implemented;
   customer notes no longer depend on matching the customer name. Tag aggregation
   and expanded order-file matching remain to implement.
6. Daily Review, summaries, history, autosave and opt-in reminder.
7. Dense file views and selection preview.
8. Customer + order/payment file aggregation and relation navigation.
9. Notes title-only list, created/manual order, tags, slash menu, typography.
10. 3D staging, cross-section movement, confirmed real oversize geometry.
11. Camera yaw/pitch directions centralized.
12. Removable offline license: signed payload, public-only client, protected local trial.
13. Full zh-CN/en audit, preserving workspace/selection on language change.
14. Tests, Release, installer excluding license_tools, run and keep open.

## Decisions

- Calendar continues to show completed records according to its existing policy.
  A multi-day task remains one record and renders compact entries with the same ID.
- Postponement is a transaction, rechecks current open/overdue state and changes
  only due date (plus existing bookkeeping), not historical start date.
- V10 overrides V9 note-preview requirements: eventual note list is title only.
- Existing quote/code blocks must remain readable and preserved even though they
  will no longer be offered as new block types.
- Trial/license keys and generator must never enter installer contents. The
  September 13 continuation initializes an internal issuer and enables the gate
  in its new trial preview; it does not replace or start an installed V9 app.

The installed application is not replaced automatically. Current acceptance is
manual, per the user's later explicit override of the original testing workflow.

## Verification notes

- Task/repository/UI focused run: 17 tests passed.
- CRM/repository/UI focused run: 21 tests passed.
- Search plus V7 regression: 11 tests passed.
- First full run exposed one outdated V5 assertion expecting collapsed customer
  basic information. Updated it for V10's explicit default expansion, retaining
  collapse/reopen and customs-information persistence checks.
- A new search regression exposed a branch-boundary defect in the in-progress
  search edit; fixed it and reran the focused search tests successfully.
- Permanent search exposed a short-window rail overflow in the full suite.
  The module area now scrolls while avatar/search and tools/settings stay outside
  that scrolling region. The previously failing palette test now passes.
- Today retains manual reordering within its active group; overdue stays date
  descending. A new workspace test covers grouping, confirmation, and restored
  drag handles after postponement (4 V10 Task tests passed together).
- Latest analyzer: 0 issues. Full regression rerun: **190 tests passed**
  (`artifacts/v10-regression.log`, 2026-09-09). No V10 release/installer has been
  produced yet; steps 5 (remaining tag/order-file work) through 15 remain pending.

Source input remains plain text in the UI. Existing source entities/IDs are reused
or created internally so legacy source associations survive without a schema
migration. User-entered source values are never translated.

## 2026-09-10 continuation: note tag foundation and editor

- Schema 12 adds NoteTagLinks, using shared Tags without merging FileTags.
- Bottom note tag entry adds/creates on Enter, strips leading # and normalizes
  whitespace/case for reuse. Removal only removes this note's association.
- Global note search now includes linked tag names, excluding deleted notes.
- Cleanup preserves note-only tags and deleted-note links needed for restoration.
  CRM global tag deletion refuses note-referenced tags with an explanatory message.
- Added real isolated schema 11 → 12 preservation test, lifecycle/search test and
  320px editor interaction test. Focused repository regressions: 16 passed;
  new tag tests: 3 passed. The initial widget finder assumed a default cancel icon;
  changed it to the accessible delete tooltip and reran successfully.
- No production database was used, no running application was stopped or replaced.
- Final checks for this checkpoint: `flutter analyze` — no issues; full
  `flutter test --reporter expanded` — **193 passed**, 2026-09-10 (2m23s).
- Still pending: global tag result counts/exact navigation, tag search suggestions,
  remaining V10 steps and final release/installer. This is a checkpoint, not V10 completion.

## Next continuation: unified tag results

- Global search includes a tag group with distinct active customer/order/file/note
  counts. Matching names across shared Tags and FileTags aggregate for display;
  their independent definitions and relations are unchanged.
- Selecting a tag stays in the palette and queries exact associations, with an
  explicit removable filter. Result rows use the existing entity navigation.
  Ordinary title matches cannot leak into the tag-filtered result set.
- Removed/deleted records do not count. Refreshing a query clears stale results;
  generation checks ignore stale asynchronous responses. Failed queries offer retry.
- New synthetic tests cover all four counts, exact matching, soft deletion and
  entering/leaving a tag filter. Focused search/UI regression: 9 tests passed.
- Remaining scope still includes order-related file search, note tag suggestions,
  subsequent V10 stages and release/installer validation. No live data or running
  executable was replaced in this continuation.
- Verification: analyzer no issues; complete regression **195 passed** (2m02s,
  2026-09-10). A pre-existing Drift multi-instance warning appeared in the isolated
  backup-restore test; that test passed. No warning suppression was added.

## Order attachment search and note tag suggestions

- File browser/search now resolves active order/payment/cost owners to their
  order and customer. Queries include order number, company/customer name and
  stored filename; result subtitles show customer and order together.
- No attachment is copied or deleted. Deleted business owners cease contributing
  search terms while the canonical file stays searchable by its own name.
  CRM-hidden file queries still exclude business attachments.
- Note tag input now offers at most five active, unlinked existing tags. Clicking
  a suggestion reuses the definition; Enter keeps add/create behavior. Loading
  failures offer retry and suggestions remain within a compact scrolling area.
- Added isolated file association/deletion tests and expanded the 320px note tag
  editor test to select an existing suggestion. One test needed a pump before
  awaiting its asynchronous provider; fixed without changing production timing.
- No schema change, dependency upgrade or live application replacement in this step.
- Verification: analyzer no issues; full regression **196 passed** (2m02s).
  A concurrently attempted focused test hit the Windows native SQLite DLL lock;
  no cache deletion or process termination was used. Tests are subsequently run
  serially. Daily Review and remaining V10 work are not yet implemented.

## 2026-09-12 continuation: Daily Review

- Added schema 13 DailyReviews without replacing existing data. Independent
  local-day records hold nine answers with transactional per-field autosave.
- Task sidebar opens the review page; Today, Yesterday and recent dates retain
  separate answers. Save failures retain pending edits with retry; the window
  close guard flushes review sessions before allowing exit.
- Summary counts read existing business records. Historical open-task state and
  order modification counts are explicitly described as current-state queries,
  not historical snapshots.
- Added opt-in reminder settings (default off), configurable time and daily
  deduplication. Notifications navigate to the review page.
- Formatting completed; analyzer reports no issues. Five focused tests passed:
  autosave/retry, summary, schema 12 upgrade/persistence, reminder deduplication,
  and a 400px review page with date switching. Tests use isolated data/fakes;
  native notification delivery is not established by these tests.
- Full regression completed: **201 tests passed** (2m12s), analyzer **0 issues**.
  The previously observed isolated backup-restore Drift multi-instance warning
  remains visible; the backup test passed and no warning suppression was added.
  No executable/installer was replaced. Files
  and Notes UI polish, container work, licensing, complete localization and
  final release acceptance remain pending. This is not V10 completion.

## Files UI checkpoint (2026-09-12)

- Files default to small icons (36px); the view menu offers medium (72px) and
  list mode. Selection survives mode changes. File names use 13px type and
  metadata 12px; list rows are 38px at normal text scale, growing with text scale.
- List columns stay on one line. Narrow lists scroll horizontally instead of
  wrapping metadata or dropping fields. Desktop selection opens a 280px preview;
  below 800px available browser width, preview moves below the list.
- Preview offers image rendering, file metadata/tags and the existing system-open
  action. No PDF/Office/video renderer or dependency was added. Folder selection
  and chevron expansion already had separate handlers; new tests verify this
  behavior and direct-child filtering without rewriting the shared tree.
- Two focused tests pass, including full workspace interaction and unit-sized
  labels. Rendered synthetic screenshots inspected: `artifacts/v10-files-list.png`
  and `artifacts/v10-files-narrow.png`; small/preview captures also generated.
- Important verification boundary: an attempted real disk-image test stalled in
  Windows test-runner thumbnail decoding (bounded timeout), then retained a file
  handle. It did not prove rendered pixels. This native decoding scenario was
  removed from the widget-only test, not marked passed or fixed by changing
  production decoding. Real image thumbnail/preview remains a Windows acceptance
  item. No Office/PDF native-open or drag-out acceptance is claimed here.
- Final checks: analyzer **0 issues**, full regression **203 passed** (2m22s).
  The existing isolated backup multi-instance warning remains unsuppressed.
  `artifacts/v10-files-image.png` is a failed diagnostic capture, not accepted
  visual evidence; only small/preview/list/narrow captures belong to this checkpoint.
  Customer/Order smart collection expansion and
  subsequent V10 work remain pending; no live database or executable replaced.

## 2026-09-13: development preview, manual acceptance requested

- User explicitly requested no analyzer, automatic validation or regression runs.
  This continuation only formats, generates required Drift bindings and compiles
  a Windows preview. Previous 203-test result does not apply to these changes.
- Customer collection now joins customer/order/payment/cost attachments. Preview
  relation capsules navigate by resolved IDs; order navigation clears customer
  filtering. Relations are virtual, not copied into file tag definitions.
- Schema 14 additively adds nullable WorkspaceNotes.manualSortOrder. Default note
  lists sort by creation time; ordinary folders offer explicit up/down ordering.
  Moving to another folder clears the old folder's manual index.
- Note lists are title-only; editor shows timestamps, compact typography and
  slash-command selection. New creation menus exclude quote/code while persisted
  blocks and their content remain supported. Note title/tag search added.
- Camera orbit direction is inverted centrally. No staging/cross-section/overflow
  behavior is claimed complete, and no license gate is present in this preview.
- Manual checklist and remaining implementation gaps:
  `docs/release/v10-preview-20260913-manual-testing.md`.
- Windows Release compilation completed (148.5s), followed by installer generation:
  `dist/Fly-V10-Preview-20260913.exe` (Inno Setup completed in 14.953s).
  No automatic tests/analyzer or installer execution were performed this turn.
  The installer tool reports "Non-commercial use only"; commercial tooling
  authorization remains to be confirmed before a sales release. This checkpoint
  must not be described as final V10 delivery or a licensed sales release.
