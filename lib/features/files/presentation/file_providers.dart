import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/data_root_providers.dart';
import '../../../shared/data/workspace_folder_repository.dart';
import '../../tasks/presentation/task_providers.dart';
import '../data/managed_file_repository.dart';
import '../data/managed_file_storage.dart';
import '../data/thumbnail_cache.dart';
import '../data/file_folder_actions.dart';
import '../data/media_import_service.dart';

final mediaImportServiceProvider = Provider((ref) => MediaImportService());

final fileFolderActionsProvider = Provider(
  (ref) => FileFolderActions(
    ref.watch(databaseProvider),
    ref.watch(fileFolderRepositoryProvider),
    ref.watch(thumbnailCacheProvider),
  ),
);

final thumbnailCacheProvider = Provider(
  (ref) => ThumbnailCache(ref.watch(managedFileStorageProvider)),
);

final managedFileRepositoryProvider = Provider(
  (ref) => ManagedFileRepository(ref.watch(databaseProvider)),
);
final managedFileStorageProvider = Provider((ref) {
  final root = ref.watch(dataRootPathProvider);
  if (root == null) throw StateError('数据目录尚未初始化');
  return ManagedFileStorage(root);
});
final fileFolderRepositoryProvider = Provider(
  (ref) => WorkspaceFolderRepository(
    ref.watch(databaseProvider),
    WorkspaceFolderKind.files,
  ),
);
final fileFoldersProvider = StreamProvider(
  (ref) => ref.watch(fileFolderRepositoryProvider).watch(),
);
final deletedFileFoldersProvider = StreamProvider(
  (ref) => ref.watch(fileFolderRepositoryProvider).watch(deleted: true),
);
final libraryTagsProvider = StreamProvider(
  (ref) => ref.watch(managedFileRepositoryProvider).watchTags(),
);
