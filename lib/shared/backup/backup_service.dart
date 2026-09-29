import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../../core/database/app_database.dart';
import '../../config/app_version.dart';
import 'library_backup_store.dart';

class BackupSettings {
  const BackupSettings({
    this.enabled = true,
    this.retentionDays = 7,
    this.directory,
  });

  final bool enabled;
  final int retentionDays;
  final String? directory;

  BackupSettings copyWith({
    bool? enabled,
    int? retentionDays,
    String? directory,
  }) => BackupSettings(
    enabled: enabled ?? this.enabled,
    retentionDays: retentionDays ?? this.retentionDays,
    directory: directory ?? this.directory,
  );
}

class BackupMetadata {
  const BackupMetadata({
    required this.backupVersion,
    required this.appVersion,
    required this.databaseSchemaVersion,
    required this.createdAt,
    this.dataRootPath,
  });

  final int backupVersion;
  final String appVersion;
  final int databaseSchemaVersion;
  final DateTime createdAt;
  final String? dataRootPath;

  Map<String, Object?> toJson() => {
    'backupVersion': backupVersion,
    'appVersion': appVersion,
    'databaseSchemaVersion': databaseSchemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (dataRootPath != null) 'dataRootPath': dataRootPath,
  };

  factory BackupMetadata.fromJson(Map<String, Object?> json) => BackupMetadata(
    backupVersion: (json['backupVersion'] as num?)?.toInt() ?? 0,
    appVersion: json['appVersion'] as String? ?? '',
    databaseSchemaVersion:
        (json['databaseSchemaVersion'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    dataRootPath: json['dataRootPath'] as String?,
  );
}

class PreparedRestore {
  const PreparedRestore({required this.directory, required this.metadata});

  final Directory directory;
  final BackupMetadata metadata;

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class FlyBackupService {
  FlyBackupService({
    required this.database,
    required this.dataRootPath,
    this.appVersion = flyAppVersion,
  });

  final AppDatabase database;
  final String dataRootPath;
  final String appVersion;

  static const backupVersion = 2;
  static const _settingEnabled = 'backup.enabled';
  static const _settingRetention = 'backup.retentionDays';
  static const _settingDirectory = 'backup.directory';
  static const _settingLastDate = 'backup.lastDate';

  void _checkBackupDirectory(String directory) {
    final root = p.normalize(p.absolute(dataRootPath));
    final output = p.normalize(p.absolute(directory));
    final defaultDirectory = p.join(root, 'backups');
    if (p.isWithin(root, output) && !p.equals(output, defaultDirectory)) {
      throw ArgumentError.value(
        directory,
        'directory',
        '数据目录内只允许使用 FlyData/backups；其他位置会使备份递归包含自身。',
      );
    }
  }

  Future<BackupSettings> loadSettings() async {
    final rows =
        await (database.select(database.appSettings)..where(
              (row) => row.key.isIn([
                _settingEnabled,
                _settingRetention,
                _settingDirectory,
              ]),
            ))
            .get();
    final values = {for (final row in rows) row.key: row.value};
    final retention = int.tryParse(values[_settingRetention] ?? '') ?? 7;
    return BackupSettings(
      enabled: values[_settingEnabled] != 'false',
      retentionDays: retention == 30 ? 30 : 7,
      directory: (values[_settingDirectory]?.trim().isEmpty ?? true)
          ? null
          : values[_settingDirectory],
    );
  }

  Future<void> saveSettings(BackupSettings settings) async {
    final now = DateTime.now();
    for (final entry in {
      _settingEnabled: settings.enabled.toString(),
      _settingRetention: settings.retentionDays.toString(),
      _settingDirectory: settings.directory ?? '',
    }.entries) {
      await database
          .into(database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: entry.key,
              value: entry.value,
              updatedAt: now,
            ),
          );
    }
  }

  Future<File?> runDailyBackupIfDue({DateTime? now}) async {
    final settings = await loadSettings();
    if (!settings.enabled) return null;
    final current = now ?? DateTime.now();
    final last = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(_settingLastDate))).getSingleOrNull();
    final today = _dateKey(current);
    if (last?.value == today) return null;
    final result = await createBackup(
      directory: settings.directory,
      now: current,
    );
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _settingLastDate,
            value: today,
            updatedAt: current,
          ),
        );
    await cleanup(
      settings.retentionDays,
      directory: settings.directory,
      now: current,
    );
    return result;
  }

  Future<File> createBackup({
    String? directory,
    DateTime? now,
    bool preRestore = false,
  }) async {
    final createdAt = now ?? DateTime.now();
    final outputDirectory = Directory(
      directory == null || directory.trim().isEmpty
          ? p.join(dataRootPath, 'backups')
          : p.normalize(p.absolute(directory)),
    );
    _checkBackupDirectory(outputDirectory.path);
    await outputDirectory.create(recursive: true);
    final prefix = preRestore ? 'PreRestore' : 'FlyBackup';
    final stamp =
        '${createdAt.year.toString().padLeft(4, '0')}'
        '${createdAt.month.toString().padLeft(2, '0')}'
        '${createdAt.day.toString().padLeft(2, '0')}-'
        '${createdAt.hour.toString().padLeft(2, '0')}'
        '${createdAt.minute.toString().padLeft(2, '0')}'
        '${createdAt.second.toString().padLeft(2, '0')}';
    final output = File(p.join(outputDirectory.path, '$prefix-$stamp.zip'));
    final stage = await Directory.systemTemp.createTemp('fly-backup-stage-');
    try {
      final snapshot = p.join(stage.path, 'fly.db');
      await database.customStatement('VACUUM INTO ?', [snapshot]);
      await _copyBusinessData(Directory(dataRootPath), stage);
      await LibraryBackupStore().snapshot(
        dataRoot: dataRootPath,
        backupDirectory: outputDirectory.path,
        stage: stage.path,
      );
      final metadata = BackupMetadata(
        backupVersion: backupVersion,
        appVersion: appVersion,
        databaseSchemaVersion: database.schemaVersion,
        createdAt: createdAt,
      );
      await File(p.join(stage.path, 'metadata.json')).writeAsString(
        const JsonEncoder.withIndent(' ').convert(metadata.toJson()),
        flush: true,
      );
      final encoder = ZipFileEncoder();
      await encoder.zipDirectoryAsync(stage, filename: output.path);
      return output;
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  Future<void> cleanup(
    int retentionDays, {
    String? directory,
    DateTime? now,
  }) async {
    final root = Directory(
      directory == null || directory.trim().isEmpty
          ? p.join(dataRootPath, 'backups')
          : p.normalize(p.absolute(directory)),
    );
    _checkBackupDirectory(root.path);
    if (!await root.exists()) return;
    final cutoff = (now ?? DateTime.now()).subtract(
      Duration(days: retentionDays),
    );
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! File ||
          !RegExp(r'^FlyBackup-\d{8}-\d{6}\.zip$')
              .hasMatch(p.basename(entry.path))) {
        continue;
      }
      if ((await entry.lastModified()).isBefore(cutoff)) await entry.delete();
    }
  }

  Future<PreparedRestore> prepareRestore(String packagePath) async {
    final package = File(packagePath);
    if (!await package.exists() ||
        p.extension(package.path).toLowerCase() != '.zip') {
      throw const FormatException('请选择有效的 Fly ZIP 备份包。');
    }
    final stage = await Directory.systemTemp.createTemp('fly-restore-stage-');
    try {
      // A disk-backed stream avoids loading a potentially large ZIP into RAM.
      final input = InputFileStream(package.path);
      try {
        final archive = ZipDecoder().decodeBuffer(input, verify: true);
        try {
          await extractArchiveToDiskAsync(
            archive,
            stage.path,
            asyncWrite: true,
          );
        } finally {
          await archive.clear();
        }
      } finally {
        await input.close();
      }
      final metadataFile = File(p.join(stage.path, 'metadata.json'));
      final databaseFile = File(p.join(stage.path, 'fly.db'));
      if (!await metadataFile.exists() || !await databaseFile.exists()) {
        throw const FormatException('备份缺少 metadata.json 或 fly.db。');
      }
      final decoded = jsonDecode(await metadataFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('备份元数据格式无效。');
      }
      final metadata = BackupMetadata.fromJson(decoded);
      if (metadata.backupVersion < 1 ||
          metadata.backupVersion > backupVersion) {
        throw const FormatException('当前 Fly 不支持该备份包版本。');
      }
      if (metadata.databaseSchemaVersion > database.schemaVersion) {
        throw StateError(
          '备份数据库版本 ${metadata.databaseSchemaVersion} 高于当前版本 '
          '${database.schemaVersion}，无法安全恢复。',
        );
      }
      if (metadata.backupVersion >= 2) {
        await LibraryBackupStore().restore(
          packageDirectory: package.parent.path,
          stage: stage.path,
        );
      }
      final verification = AppDatabase(NativeDatabase(databaseFile));
      try {
        final result = await verification
            .customSelect('PRAGMA integrity_check')
            .get();
        if (result.isEmpty || result.first.data.values.first != 'ok') {
          throw const FormatException('备份数据库完整性检查失败。');
        }
      } finally {
        await verification.close();
      }
      return PreparedRestore(directory: stage, metadata: metadata);
    } on Object {
      if (await stage.exists()) await stage.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> commitRestore(PreparedRestore prepared) async {
    final target = Directory(dataRootPath);
    final rollback = Directory(
      p.join(
        target.parent.path,
        '.fly-restore-rollback-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await rollback.create(recursive: true);
    final managedNames = <String>{
      'fly.db',
      'fly.db-wal',
      'fly.db-shm',
      'attachments',
      'orders',
      'customers',
      for (final entity in await prepared.directory.list().toList())
        if (p.basename(entity.path) != 'metadata.json') p.basename(entity.path),
    };
    final movedCurrent = <String>[];
    final movedIncoming = <String>[];
    try {
      for (final name in managedNames) {
        final currentPath = p.join(target.path, name);
        if (await FileSystemEntity.type(currentPath) ==
            FileSystemEntityType.notFound) {
          continue;
        }
        await _renameEntity(currentPath, p.join(rollback.path, name));
        movedCurrent.add(name);
      }
      for (final entity in await prepared.directory.list().toList()) {
        final name = p.basename(entity.path);
        if (name == 'metadata.json') continue;
        await _renameEntity(entity.path, p.join(target.path, name));
        movedIncoming.add(name);
      }
      if (!await File(p.join(target.path, 'fly.db')).exists()) {
        throw StateError('恢复后的数据目录缺少 fly.db。');
      }
    } on Object {
      for (final name in movedIncoming.reversed) {
        await _deleteEntity(p.join(target.path, name));
      }
      for (final name in movedCurrent.reversed) {
        await _renameEntity(
          p.join(rollback.path, name),
          p.join(target.path, name),
        );
      }
      rethrow;
    } finally {
      if (await rollback.exists()) await rollback.delete(recursive: true);
      await prepared.dispose();
    }
  }

  Future<void> _copyBusinessData(Directory source, Directory target) async {
    await for (final entity in source.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if ({
        'fly.db',
        'fly.db-wal',
        'fly.db-shm',
        'backups',
        'logs',
        'files',
        'cache',
        LibraryBackupStore.objectDirectory,
      }.contains(name)) {
        continue;
      }
      await _copyEntity(entity, p.join(target.path, name));
    }
  }

  Future<void> _copyEntity(FileSystemEntity entity, String destination) async {
    if (entity is File) {
      await File(destination).parent.create(recursive: true);
      await entity.copy(destination);
      return;
    }
    if (entity is Directory) {
      final directory = Directory(destination);
      await directory.create(recursive: true);
      await for (final child in entity.list(followLinks: false)) {
        await _copyEntity(child, p.join(destination, p.basename(child.path)));
      }
    }
  }

  Future<void> _renameEntity(String source, String destination) async {
    await Directory(p.dirname(destination)).create(recursive: true);
    final type = await FileSystemEntity.type(source);
    try {
      if (type == FileSystemEntityType.file) {
        await File(source).rename(destination);
      } else if (type == FileSystemEntityType.directory) {
        await Directory(source).rename(destination);
      }
    } on FileSystemException {
      final entity = type == FileSystemEntityType.file
          ? File(source)
          : Directory(source);
      try {
        await _copyEntity(entity, destination);
        await _deleteEntity(source);
      } on Object {
        // A cross-volume copy can fail after creating part of the target.
        // Remove that partial target so commitRestore can put the rollback
        // entity back at the original path without a name collision.
        await _deleteEntity(destination);
        rethrow;
      }
    }
  }

  Future<void> _deleteEntity(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.file) {
      await File(path).delete();
    } else if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    }
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
