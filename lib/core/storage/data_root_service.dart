import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DataRootInspection {
  const DataRootInspection({
    required this.path,
    required this.hasDatabase,
    required this.hasLegacyDatabase,
  });

  final String path;
  final bool hasDatabase;
  final bool hasLegacyDatabase;
}

class FlyDataRootService {
  FlyDataRootService({
    Directory? supportDirectory,
    Directory? documentsDirectory,
    TargetPlatform? platform,
  }) : this._withDirectories(supportDirectory, documentsDirectory, platform);

  FlyDataRootService._withDirectories(
    this._supportDirectory,
    this._documentsDirectory,
    this._platform,
  );

  final Directory? _supportDirectory;
  final Directory? _documentsDirectory;
  final TargetPlatform? _platform;
  static const mobileStorageChannel = MethodChannel(
    'com.flyproduct.fly/storage',
  );
  TargetPlatform get platform =>
      _platform ??
      (Platform.isAndroid
          ? TargetPlatform.android
          : Platform.isIOS
          ? TargetPlatform.iOS
          : TargetPlatform.windows);
  bool get isMobile =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  Future<String> initializeMobile() async {
    if (!isMobile) throw StateError('此操作仅适用于手机');
    final saved = await loadDataRoot();
    if (saved != null) {
      if (platform == TargetPlatform.android) {
        final accessible = await mobileStorageChannel.invokeMethod<bool>(
          'ensureAccess',
          {'path': saved},
        );
        if (accessible != true) throw StateError('请允许 Fly 访问已有的手机数据目录后重试。');
      }
      await ensureStructure(saved);
      return saved;
    }
    final shared = platform == TargetPlatform.android
        ? await mobileStorageChannel.invokeMethod<String>('sharedRoot')
        : null;
    final root = p.normalize(p.absolute(shared ?? await recommendedDataRoot()));
    await prepareFirstRun(
      root,
      useExistingDatabase: true,
      migrateLegacyDatabase: true,
    );
    return root;
  }

  Future<Directory> get _support async =>
      _supportDirectory ?? await getApplicationSupportDirectory();

  Future<File> get _settingsFile async =>
      File(p.join((await _support).path, 'settings.json'));

  Future<String?> loadDataRoot() async {
    final file = await _settingsFile;
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      final value = json is Map<String, dynamic>
          ? json['dataRootPath'] as String?
          : null;
      return value == null || value.trim().isEmpty
          ? null
          : p.normalize(p.absolute(value));
    } on Object {
      return null;
    }
  }

  Future<String> recommendedDataRoot() async {
    final documents =
        _documentsDirectory ?? await getApplicationDocumentsDirectory();
    return p.join(documents.path, isMobile ? 'fly' : 'FlyData');
  }

  Future<DataRootInspection> inspect(String path) async {
    final normalized = p.normalize(p.absolute(path));
    return DataRootInspection(
      path: normalized,
      hasDatabase: await File(p.join(normalized, 'fly.db')).exists(),
      hasLegacyDatabase: await (await legacyDatabase()).exists(),
    );
  }

  Future<File> legacyDatabase() async =>
      File(p.join((await _support).path, 'fly.sqlite'));

  Future<void> prepareFirstRun(
    String path, {
    required bool useExistingDatabase,
    required bool migrateLegacyDatabase,
  }) async {
    final root = Directory(p.normalize(p.absolute(path)));
    await _ensureStructure(root);
    final target = File(p.join(root.path, 'fly.db'));
    if (await target.exists()) {
      if (!useExistingDatabase) {
        throw StateError('目标目录已存在 fly.db，需要确认后才能使用。');
      }
    } else if (migrateLegacyDatabase) {
      final legacy = await legacyDatabase();
      if (await legacy.exists()) {
        await legacy.copy(target.path);
        for (final suffix in const ['-wal', '-shm']) {
          final sidecar = File('${legacy.path}$suffix');
          if (await sidecar.exists()) {
            await sidecar.copy('${target.path}$suffix');
          }
        }
        final legacyFiles = Directory(p.join((await _support).path, 'FlyData'));
        if (await legacyFiles.exists()) {
          await _copyDirectoryContents(legacyFiles, root, skipExisting: true);
        }
      }
    }
    await saveDataRoot(root.path);
  }

  Future<void> saveDataRoot(String path) async {
    final settings = await _settingsFile;
    await settings.parent.create(recursive: true);
    final temporary = File('${settings.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'dataRootPath': p.normalize(p.absolute(path)),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    if (await settings.exists()) await settings.delete();
    await temporary.rename(settings.path);
  }

  Future<void> ensureStructure(String path) =>
      _ensureStructure(Directory(p.normalize(p.absolute(path))));

  Future<void> migrateDataRoot(String sourcePath, String targetPath) async {
    final source = Directory(p.normalize(p.absolute(sourcePath)));
    final target = Directory(p.normalize(p.absolute(targetPath)));
    if (p.equals(source.path, target.path)) return;
    if (!await File(p.join(source.path, 'fly.db')).exists()) {
      throw StateError('旧数据目录缺少 fly.db。');
    }
    if (await target.exists() &&
        (await target.list().take(1).toList()).isNotEmpty) {
      throw StateError('新目录必须为空，避免覆盖已有数据。');
    }
    await target.create(recursive: true);
    await _copyDirectoryContents(source, target);
    if (!await _sameTree(source, target)) {
      throw StateError('数据复制校验失败，仍继续使用旧目录。');
    }
    await _ensureStructure(target);
    await saveDataRoot(target.path);
  }

  Future<void> openInFileManager(String path) async {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [p.normalize(path)]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [path]);
    } else {
      await Process.start('xdg-open', [path]);
    }
  }

  Future<void> _ensureStructure(Directory root) async {
    await root.create(recursive: true);
    for (final name in const [
      'files',
      'attachments',
      'orders',
      'customers',
      'backups',
      'logs',
    ]) {
      await Directory(p.join(root.path, name)).create(recursive: true);
    }
  }

  Future<void> _copyDirectoryContents(
    Directory source,
    Directory target, {
    bool skipExisting = false,
  }) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final destination = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectoryContents(
          entity,
          Directory(destination),
          skipExisting: skipExisting,
        );
      } else if (entity is File) {
        if (skipExisting && await File(destination).exists()) continue;
        await entity.copy(destination);
      }
    }
  }

  Future<bool> _sameTree(Directory left, Directory right) async {
    Future<Map<String, int>> inventory(Directory root) async {
      final result = <String, int>{};
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          result[p.relative(entity.path, from: root.path)] = await entity
              .length();
        }
      }
      return result;
    }

    final source = await inventory(left);
    final target = await inventory(right);
    return source.length == target.length &&
        source.entries.every((entry) => target[entry.key] == entry.value);
  }
}

class DataRootActions {
  const DataRootActions({required this.changeTo, required this.open});

  final Future<String?> Function(String targetPath) changeTo;
  final Future<void> Function() open;
}
