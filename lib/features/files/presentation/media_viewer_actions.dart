import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareViewerFile(
  BuildContext context,
  String path,
  String name,
) async {
  if (!await File(path).exists()) throw StateError('文件内容尚未下载，请检查同步状态');
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path)],
      fileNameOverrides: [name],
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}
