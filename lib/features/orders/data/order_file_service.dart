import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/attachments/attachment.dart';
import '../../../shared/attachments/attachment_storage.dart';
import '../domain/order.dart';

class StoredOrderFile {
  const StoredOrderFile({
    required this.fileName,
    required this.originalName,
    required this.relativePath,
    required this.fileSize,
    required this.mimeType,
  });

  final String fileName;
  final String originalName;
  final String relativePath;
  final int fileSize;
  final String mimeType;
}

abstract interface class OrderFileStorage {
  Future<StoredOrderFile> importFile({
    required String sourcePath,
    required String orderId,
    required OrderDocumentType documentType,
  });
  Future<String> absolutePath(String relativePath);
  Future<void> removeStoredFile(String relativePath);
}

class LocalOrderFileStorage implements OrderFileStorage {
  LocalOrderFileStorage({this.dataRootPath});

  final String? dataRootPath;

  Future<Directory> _root() async {
    if (dataRootPath != null) {
      final root = Directory(dataRootPath!);
      await root.create(recursive: true);
      return root;
    }
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'FlyData'));
    await root.create(recursive: true);
    return root;
  }

  @override
  Future<StoredOrderFile> importFile({
    required String sourcePath,
    required String orderId,
    required OrderDocumentType documentType,
  }) async {
    final root = await _root();
    final stored = await LocalAttachmentStorage(dataRootPath: root.path)
        .importFile(
          ownerType: AttachmentOwnerType.order,
          ownerId: orderId,
          sourcePath: sourcePath,
        );
    return StoredOrderFile(
      fileName: stored.fileName,
      originalName: stored.originalName,
      relativePath: stored.relativePath,
      fileSize: stored.fileSize,
      mimeType: stored.mimeType,
    );
  }

  @override
  Future<String> absolutePath(String relativePath) async {
    final root = await _root();
    return p.join(root.path, relativePath);
  }

  @override
  Future<void> removeStoredFile(String relativePath) async {
    final file = File(await absolutePath(relativePath));
    if (await file.exists()) await file.delete();
  }
}

abstract interface class OrderFileOpener {
  Future<void> open(String absolutePath);
}

class PlatformOrderFileOpener implements OrderFileOpener {
  @override
  Future<void> open(String absolutePath) =>
      PlatformAttachmentOpener().open(absolutePath);
}
