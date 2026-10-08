# Fly Knowledge publishing and safety

The Knowledge Hub separates signed official articles from private notes. Articles are Markdown sources with front matter; Fly compiles them to a restricted HTML subset, adds a theme-aware shell, and keeps navigation inside Flutter. Private notes remain in the existing SQLite note tables and are never copied into a knowledge pack. The only database additions are a nullable source-article link and the local favorites table.

## Developer workflow

1. Build/run with `--dart-define=ENABLE_KNOWLEDGE_EDITOR=true`. Consumer builds leave this false; there is no password backdoor.
2. Open **资料库 → 编辑资料**. The first developer launch copies the 14 bundled source articles into `FlyData/knowledge/developer`. Editing this draft does not change the consumer's active signed pack.
3. Add categories, change their order, create articles, edit front matter/Markdown, insert an image or paste a screenshot. Image insertion converts to bounded PNG and stores a managed `assets/images/…` path. Preview uses the same sanitizing compiler and HTML viewer as the consumer.
4. Increment the pack version before export. Select an external Ed25519 signing-seed file when prompted. The private seed is not saved by Fly. The exported `.flykb` goes to `FlyData/dist/knowledge/`.
5. In a consumer build, **Settings → Knowledge Hub → Import official pack** verifies the manifest signature, all file hashes, version, article structure, and generated HTML before replacing the active pack. Failed verification or extraction leaves the active pack and personal notes intact.

`tool/knowledge_keygen.dart` creates the publisher's seed under the Git-ignored `license_tools/private/` directory. Keep that seed in a secure offline backup. Losing it means existing consumer builds cannot accept packs signed with a new key. To rotate, ship a new consumer build with a new `KNOWLEDGE_PUBLIC_KEY` and sign future packs with the corresponding seed. Never commit, email, or include the seed in an installer.

## Pack layout

`.flykb` is a bounded ZIP with `manifest.json`, `categories.json`, `articles/*.md`, `rendered/*.html`, `assets/`, `search/index.json`, and `signature/manifest.sig`. The manifest contains SHA-256 hashes for every payload file; its raw bytes are signed with Ed25519. The compiler re-renders each imported Markdown article and checks the result against the packaged HTML. A ZIP preflight rejects unsafe paths, excessive uncompressed size, ZIP64, and multi-disk archives before in-memory decompression.

All bundled demonstration articles are original placeholders, not copies of reference-course text or imagery. Categories can remain empty until the publisher writes original material.

## Access and copying

All current seed articles are free. When a local license expires, Fly still provides a standalone, read-only view of free official knowledge. Personal notes and other workspaces remain behind the existing license gate. `accessLevel` is retained in the article domain for later product policy; it is not a payment or cloud entitlement system.

`copyPolicy` controls ordinary UI selection/copy: `none`, `snippet` (`:::copyable` only), or `full`. This is not DRM. Screenshots, OCR, and inspection of locally displayed data cannot be fully prevented.

No pack-supplied JavaScript runs. A fixed nonce-scoped viewer bridge handles only validated image and link interactions. External HTTPS links open in the system browser; `fly://knowledge/<id>` stays inside Fly. Assets are validated and embedded as bounded local data URIs.

## Future distribution

The repository loads a bundled seed or an active verified local pack. Cloud distribution can later provide `.flykb` bytes to the same verification/import boundary without changing article, category, search, favorite, viewer, or note-link domains.
