# Fly V9 implementation checkpoint

Status: in development; not a release acceptance report.

## Implemented foundations

- Additive schema 11 migration for file folders, file tags, note folders, notes,
  JSON blocks and canonical attachment metadata. Existing tasks and attachments
  have migration regression coverage.
- Independent file/note folder trees with cycle protection, soft deletion and
  subtree-scoped restoration.
- Streamed managed-file imports, SHA256 duplicate decisions and cancellation
  cleanup. Business attachments retain their ownership.
- Incremental library backup objects and manifests, with integrity and path
  validation before restoration. Backup archives and their `.fly-file-objects`
  directory must be retained together.
- Reusable folder tree and structured note block editor: headings, lists,
  checklist, quote, divider, table, code, media host callbacks, stable-ID reorder,
  duplication and Markdown shortcuts.
- Serialized note autosave session with optimistic revisions. Edits made during
  a save are persisted in a subsequent write. Conflicts retain the local draft.
  Hosts flush before switching notes; sessions remain alive across primary-module
  navigation. Draft snapshots also persist in SQLite AppSettings and are restored
  after restart. Revision conflicts can be recovered as a new note without
  overwriting the original; copied blocks receive new IDs.
- Windows normal-close handshake waits for note saves. A failed save permits
  closing only if the current draft was persisted; an unwritten draft blocks
  closing with a visible message. This does not promise survival of forced
  process termination or power loss before a write completes.
- Files and Notes primary destinations, responsive workspaces, file grid/list,
  folder breadcrumb, import progress/cancellation, duplicate choices, soft-delete
  restore, tag editing/AND filtering, customer collection visibility, note
  favorites/moving/media imports and global-search result navigation.
- Windows shell IDataObject clipboard and COPY-only OLE drag-source adapter.
  Context-menu copy and Ctrl+C publish the selected file; the small drag-out
  handle initiates native transfer separately from internal folder dragging.
- Disk image-thumbnail cache; unsupported/broken media falls back to icons.
- Folder context-menu disk location resolves current direct files, including
  files moved logically from another folder. The location picker explains why
  a logical folder may not correspond to one physical directory.
- Folder subtree deletion clears associated disposable thumbnails; cache cleanup
  failures are reported without undoing recoverable metadata deletion. Deleted
  entries no longer regenerate thumbnails or open on double-click.
- Note list previews observe the first three blocks for visible rows, normalize
  whitespace and limit excerpts to 160 Unicode code points. Autosaved edits
  update the preview without reopening the module.

## Checks at this checkpoint

- Formatting applied to authored changes.
- `flutter analyze`: no issues.
- 21 V9 focused tests passed (foundation, backup, block editor, save session,
  browser queries and workspace interaction).
- Full regression on 2026-09-09: 183 tests passed, including restart recovery,
  failed draft writes, conflict-copy workspace interaction, folder cache cleanup
  and Unicode-safe note previews.
- Full regression output: `artifacts/v9-regression.log`.
- Windows Release build passed on 2026-09-09 (latest: 188.0 seconds), explicitly targeting
  `lib/main.dart`, with native transfer and normal-close adapters. This is build
  evidence, not Explorer/WeChat drag-and-drop or close-handshake acceptance.
- Rendered and visually inspected isolated-data screenshots with real Chinese
  and Material fonts: `artifacts/v9-files.png`, `artifacts/v9-notes.png`.
- Launched the latest normal-entry Release executable directly from the project;
  the desktop window inventory confirmed its exact Release path and a Fly window.
  Left it running for user testing. The installed application was not replaced.

## Remaining acceptance work

1. Native desktop close/restart smoke acceptance. Durable draft restart,
   conflict-copy recovery and disk-write failure have automated coverage;
   normal-close platform behavior still needs desktop interaction acceptance.
2. Audit large-library performance and complete end-user acceptance of logical
   folder disk-location picking; native multi-file selection is not implemented.
3. Windows native drag-out and file clipboard; actual Explorer and WeChat checks
   must be recorded, not inferred from source or unit tests.
4. End-to-end migration/backup workflow, rendered UI checks, final release build,
   installer and launch after all required functionality passes.

Existing production data has not been used as test fixtures. V9 is not yet a
fully accepted release or installer replacement.
