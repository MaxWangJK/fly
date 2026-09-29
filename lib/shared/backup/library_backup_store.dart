import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Immutable sidecar objects prevent each daily ZIP from duplicating videos.
/// Objects are intentionally not garbage-collected with individual snapshots.
class LibraryBackupStore {
  static const manifestName = 'library-manifest.json';
  static const objectDirectory = '.fly-file-objects';
  Future<void> snapshot({
    required String dataRoot,
    required String backupDirectory,
    required String stage,
  }) async {
    final library = Directory(p.join(dataRoot, 'files'));
    final entries = <Map<String, Object>>[];
    if (await library.exists()) {
      await for (final entity in library.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || entity.path.endsWith('.importing')) continue;
        final hash = (await sha256.bind(entity.openRead()).first).toString();
        final size = await entity.length();
        final object = File(p.join(backupDirectory, objectDirectory, hash));
        if (!await object.exists()) {
          await object.parent.create(recursive: true);
          final partial = File('${object.path}.${const Uuid().v7()}.partial');
          try {
            await entity.copy(partial.path);
            if ((await sha256.bind(partial.openRead()).first).toString() !=
                hash) {
              throw StateError('备份期间库文件发生变化，请重试');
            }
            await partial.rename(object.path);
          } finally {
            if (await partial.exists()) await partial.delete();
          }
        } else if (await object.length() != size ||
            (await sha256.bind(object.openRead()).first).toString() != hash) {
          throw StateError('文件备份对象校验失败：$hash');
        }
        entries.add({
          'relativePath': p.relative(entity.path, from: dataRoot),
          'sha256': hash,
          'size': size,
        });
      }
    }
    await File(
      p.join(stage, manifestName),
    ).writeAsString(jsonEncode({'version': 1, 'files': entries}), flush: true);
  }

  Future<void> restore({
    required String packageDirectory,
    required String stage,
  }) async {
    final manifest = File(p.join(stage, manifestName));
    if (!await manifest.exists()) throw const FormatException('备份缺少库文件清单');
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['files'] is! List) {
      throw const FormatException('库文件清单格式无效');
    }
    final targets = <String>{};
    for (final value in decoded['files'] as List) {
      if (value is! Map ||
          value['relativePath'] is! String ||
          value['sha256'] is! String ||
          value['size'] is! int) {
        throw const FormatException('无效库文件条目');
      }
      final relative = value['relativePath'] as String;
      final hash = value['sha256'] as String;
      final target = p.normalize(p.join(stage, relative));
      if (p.isAbsolute(relative) ||
          !p.isWithin(p.join(stage, 'files'), target) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
          !targets.add(target.toLowerCase())) {
        throw const FormatException('库文件路径或摘要无效');
      }
      final object = File(p.join(packageDirectory, objectDirectory, hash));
      if (!await object.exists() || await object.length() != value['size']) {
        throw StateError('缺少备份文件对象，请同时复制 .fly-file-objects 文件夹');
      }
      if ((await sha256.bind(object.openRead()).first).toString() != hash) {
        throw StateError('备份文件摘要校验失败');
      }
      await File(target).parent.create(recursive: true);
      await object.copy(target);
    }
    await Directory(p.join(stage, 'files')).create(recursive: true);
    await manifest.delete();
  }
}
