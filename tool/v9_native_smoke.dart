// Explicit test entry point; never reads the user's configured Fly data root.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_providers.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/presentation/files_workspace.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/attachments/attachment_storage.dart';
import 'package:fly/shared/design_system/app_theme.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = await Directory.systemTemp.createTemp('fly-v9-native-');
  final source = File(p.join(root.path, '中文 文件传输验证.txt'));
  await source.writeAsString(
    'Fly V9 synthetic file transfer verification. No customer data.',
  );
  final destination = Directory(p.join(root.path, 'export'));
  await destination.create();
  final db = AppDatabase(NativeDatabase.memory());
  await db.ensureBuiltInData();
  final imported = await ManagedFileStorage(root.path).import(source.path);
  await ManagedFileRepository(db).commit(imported);
  // ignore: avoid_print
  print('V9_NATIVE_TEST_ROOT=${root.path}');
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dataRootPathProvider.overrideWithValue(root.path),
      ],
      child: MaterialApp(
        theme: FlyTheme.light(),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('V9 文件传输验证（隔离数据）'),
            actions: [
              TextButton(
                onPressed: () =>
                    PlatformAttachmentOpener().open(destination.path),
                child: const Text('打开验证目录'),
              ),
            ],
          ),
          body: const FilesWorkspace(),
        ),
      ),
    ),
  );
}
