import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/fly_localizations.dart';

class ImageFileViewer extends StatelessWidget {
  const ImageFileViewer({required this.path, required this.name, super.key});
  final String path, name;
  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    key: const ValueKey('image-file-viewer'),
    child: Scaffold(
      appBar: AppBar(
        title: Text(name),
        leading: IconButton(
          tooltip: context.l10n.isZh ? '关闭' : 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SizedBox.expand(
        child: InteractiveViewer(
          minScale: .5,
          maxScale: 8,
          child: Center(
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  Text(context.l10n.t('fileImageUnavailable')),
            ),
          ),
        ),
      ),
    ),
  );
}
