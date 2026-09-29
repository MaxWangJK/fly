import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'attachment.dart';

class StoredAttachment {
  const StoredAttachment({
    required this.id,
    required this.fileName,
    required this.originalName,
    required this.relativePath,
    required this.fileSize,
    required this.mimeType,
  });

  final String id;
  final String fileName;
  final String originalName;
  final String relativePath;
  final int fileSize;
  final String mimeType;
}

class LocalAttachmentStorage {
  LocalAttachmentStorage({required this.dataRootPath});

  final String dataRootPath;
  final Uuid _uuid = const Uuid();

  Future<StoredAttachment> importFile({
    required AttachmentOwnerType ownerType,
    required String ownerId,
    required String sourcePath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw StateError('文件不存在：$sourcePath');
    final id = _uuid.v7();
    final originalName = p.basename(source.path);
    final safeName = originalName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final fileName = '$id-$safeName';
    final relativePath = p.join(
      'attachments',
      ownerType.folder,
      ownerId,
      fileName,
    );
    final target = File(p.join(dataRootPath, relativePath));
    await target.parent.create(recursive: true);
    await source.copy(target.path);
    return StoredAttachment(
      id: id,
      fileName: fileName,
      originalName: originalName,
      relativePath: relativePath,
      fileSize: await target.length(),
      mimeType: _mimeType(originalName),
    );
  }

  String absolutePath(String relativePath) =>
      p.normalize(p.join(dataRootPath, relativePath));

  Future<void> delete(String relativePath) async {
    final file = File(absolutePath(relativePath));
    if (await file.exists()) await file.delete();
  }

  String _mimeType(String name) => switch (p.extension(name).toLowerCase()) {
    '.pdf' => 'application/pdf',
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.xls' => 'application/vnd.ms-excel',
    '.docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.doc' => 'application/msword',
    _ => 'application/octet-stream',
  };
}

class PlatformAttachmentOpener {
  Future<void> reveal(String absolutePath) async {
    if (!await File(absolutePath).exists()) throw StateError('原文件不存在');
    if (Platform.isWindows) {
      await Process.start('explorer.exe', ['/select,', absolutePath]);
    } else if (Platform.isMacOS) {
      await Process.start('open', ['-R', absolutePath]);
    } else {
      await open(p.dirname(absolutePath));
    }
  }

  Future<void> open(String absolutePath) async {
    if (Platform.isWindows) {
      await Process.start('rundll32.exe', [
        'url.dll,FileProtocolHandler',
        absolutePath,
      ]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [absolutePath]);
    } else {
      await Process.start('xdg-open', [absolutePath]);
    }
  }
}
