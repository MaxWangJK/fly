# Fly Knowledge HTML renderer evaluation (2026-10-06)

Fly is Windows-first but declares Android, iOS and macOS targets. Official articles are authored as Markdown, compiled to a constrained HTML subset, and displayed read-only. The viewer must not execute scripts supplied by a content pack.

| Option | Platforms and maintenance | Decision |
| --- | --- | --- |
| [`webview_flutter` 4.14.1](https://pub.dev/packages/webview_flutter) | Flutter-maintained; Android, iOS, macOS. No Windows implementation. | Use on Android/iOS/macOS. |
| [`webview_flutter_windows` 1.3.0](https://pub.dev/packages/webview_flutter_windows) | Maintained WebView2 fork; Windows 10 1809+, Flutter 3.44+/Dart 3.12+, WebView2 runtime required. API is independent from Flutter's `webview_flutter`. | Use on Windows behind a small platform adapter. Detect missing WebView2 and show a recoverable error. |
| [`flutter_inappwebview` 6.1.5](https://pub.dev/packages/flutter_inappwebview) | Covers all four targets in one API, but latest stable release is around two years old and Windows setup needs NuGet CLI. | Do not introduce for this feature while the actively maintained Windows fork is available. |

The two chosen adapters consume the same already-sanitized HTML. The content pack cannot supply JavaScript: the page CSP permits only Fly's fixed, nonce-scoped viewer bridge for link/image events and copy policy. Arbitrary navigation, default context menus and developer tools are disabled where supported. Open HTTPS links in the system browser; `fly://knowledge/…` links are handled by Flutter navigation. Images are validated pack assets, embedded as bounded data URIs so the viewer does not require broad `file://` access. `copyPolicy` is normal-user friction, not DRM: screenshots, OCR and local-file inspection remain possible.

The code must keep the article domain independent of either WebView package, so a future platform change only replaces the presentation adapter. Native builds and interaction checks are still required on each target; a Windows build does not prove mobile WebView behavior.
