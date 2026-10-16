import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as win;

/// Only [KnowledgeMarkdownCompiler]'s sanitized HTML may be passed here.
class KnowledgeHtmlViewer extends StatefulWidget {
  const KnowledgeHtmlViewer({
    required this.html,
    required this.onLink,
    required this.onImage,
    this.onProgress,
    super.key,
  });

  final String html;
  final ValueChanged<String> onLink;
  final ValueChanged<String> onImage;
  final ValueChanged<double>? onProgress;

  @override
  State<KnowledgeHtmlViewer> createState() => KnowledgeHtmlViewerState();
}

class KnowledgeHtmlViewerState extends State<KnowledgeHtmlViewer> {
  win.WebviewController? _windows;
  WebViewController? _mobile;
  StreamSubscription<dynamic>? _messages;
  Object? _error;
  bool _ready = false;
  int _generation = 0;

  Future<void> scrollTo(String sectionId) async {
    if (!RegExp(r'^section-[0-9]+$').hasMatch(sectionId)) return;
    final script =
        "document.getElementById('$sectionId')?.scrollIntoView({behavior:'smooth',block:'start'});";
    if (_windows case final controller?) {
      await controller.executeScript(script);
    } else if (_mobile case final controller?) {
      await controller.runJavaScript(script);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant KnowledgeHtmlViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.html == oldWidget.html) return;
    if (_windows != null) {
      unawaited(_windows!.loadStringContent(widget.html));
    } else if (_mobile != null) {
      unawaited(_mobile!.loadHtmlString(widget.html));
    }
  }

  void _message(dynamic raw) {
    if (!mounted) return;
    try {
      final value = raw is String ? jsonDecode(raw) : raw;
      if (value is! Map) return;
      final target = value['target'];
      if (target is! String) return;
      if (value['type'] == 'progress' && value['value'] is num) {
        final progress = (value['value'] as num).toDouble();
        if (progress.isFinite) widget.onProgress?.call(progress.clamp(0, 1));
      }
      if (value['type'] == 'link') widget.onLink(target);
      if (value['type'] == 'image' && target.startsWith('data:image/')) {
        widget.onImage(target);
      }
    } on FormatException {
      // A malformed viewer event has no navigation side effect.
    }
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    try {
      if (Platform.isWindows) {
        if (await win.WebviewController.getWebViewVersion() == null) {
          throw StateError('Microsoft Edge WebView2 Runtime is not installed');
        }
        final controller = win.WebviewController();
        await controller.initialize();
        await controller.setDevToolsEnabled(false);
        await controller.setDefaultContextMenusEnabled(false);
        _messages = controller.webMessage.listen(_message);
        await controller.loadStringContent(widget.html);
        if (!mounted || generation != _generation) {
          await controller.dispose();
          return;
        }
        setState(() {
          _windows = controller;
          _ready = true;
        });
      } else if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        final controller = WebViewController();
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.addJavaScriptChannel(
          'FlyBridge',
          onMessageReceived: (message) => _message(message.message),
        );
        await controller.setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (_) => NavigationDecision.prevent,
          ),
        );
        await controller.loadHtmlString(widget.html);
        if (!mounted || generation != _generation) return;
        setState(() {
          _mobile = controller;
          _ready = true;
        });
      } else {
        throw UnsupportedError('Knowledge HTML viewer is unavailable');
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_messages?.cancel());
    final controller = _windows;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('无法打开资料阅读器：$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() => _error = null);
                  unawaited(_initialize());
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return _windows != null
        ? win.Webview(_windows!)
        : WebViewWidget(controller: _mobile!);
  }
}

Future<void> previewKnowledgeImage(BuildContext context, String dataUri) async {
  final comma = dataUri.indexOf(',');
  if (comma < 0 || !dataUri.substring(0, comma).endsWith(';base64')) return;
  final bytes = base64Decode(dataUri.substring(comma + 1));
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: InteractiveViewer(
        minScale: .5,
        maxScale: 5,
        child: Image.memory(bytes, fit: BoxFit.contain),
      ),
    ),
  );
}
