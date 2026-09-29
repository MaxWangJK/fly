import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/data_root_providers.dart';
import '../../features/tasks/presentation/task_providers.dart';
import 'attachment.dart';
import 'attachment_repository.dart';
import 'attachment_storage.dart';
import 'drift_attachment_repository.dart';

final attachmentRepositoryProvider = Provider<AttachmentRepository>(
  (ref) => DriftAttachmentRepository(ref.watch(databaseProvider)),
);

final attachmentStorageProvider = Provider<LocalAttachmentStorage>((ref) {
  final root = ref.watch(dataRootPathProvider);
  if (root == null) throw StateError('Fly 数据目录尚未初始化');
  return LocalAttachmentStorage(dataRootPath: root);
});

final attachmentOpenerProvider = Provider<PlatformAttachmentOpener>(
  (ref) => PlatformAttachmentOpener(),
);

final ownerAttachmentsProvider =
    StreamProvider.family<
      List<FlyAttachment>,
      ({AttachmentOwnerType ownerType, String ownerId})
    >(
      (ref, owner) => ref
          .watch(attachmentRepositoryProvider)
          .watchOwner(owner.ownerType, owner.ownerId),
    );
