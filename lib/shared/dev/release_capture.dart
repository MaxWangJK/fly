import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ReleaseCapture extends StatefulWidget {
  const ReleaseCapture({
    required this.outputPath,
    required this.child,
    super.key,
  });

  final String outputPath;
  final Widget child;

  @override
  State<ReleaseCapture> createState() => _ReleaseCaptureState();
}

class _ReleaseCaptureState extends State<ReleaseCapture> {
  final _boundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return;
    final file = File(widget.outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: _boundaryKey, child: widget.child);
}
