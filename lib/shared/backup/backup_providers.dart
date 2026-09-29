import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/data_root_providers.dart';
import '../../features/tasks/presentation/task_providers.dart';
import 'backup_service.dart';

final backupServiceProvider = Provider<FlyBackupService>((ref) {
  final root = ref.watch(dataRootPathProvider);
  if (root == null) throw StateError('Fly 数据目录尚未初始化');
  return FlyBackupService(
    database: ref.watch(databaseProvider),
    dataRootPath: root,
  );
});

class BackupRuntimeActions {
  const BackupRuntimeActions({required this.restoreFrom});

  final Future<String?> Function(String packagePath) restoreFrom;
}

final backupRuntimeActionsProvider = Provider<BackupRuntimeActions?>(
  (ref) => null,
);
