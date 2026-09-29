import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import 'attachment.dart';
import 'attachment_repository.dart';

class DriftAttachmentRepository implements AttachmentRepository {
  DriftAttachmentRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<FlyAttachment>> watchOwner(
    AttachmentOwnerType ownerType,
    String ownerId,
  ) =>
      (_db.select(_db.attachments)
            ..where(
              (row) =>
                  row.ownerType.equals(ownerType.code) &
                  row.ownerId.equals(ownerId) &
                  row.deletedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
          .watch()
          .map((rows) => rows.map(_map).toList());

  @override
  Future<FlyAttachment> addMetadata({
    required String id,
    required AttachmentOwnerType ownerType,
    required String ownerId,
    required String fileName,
    required String originalName,
    required String relativePath,
    required String mimeType,
    required int fileSize,
    required String documentType,
  }) async {
    final now = DateTime.now();
    await _db
        .into(_db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: id,
            ownerType: ownerType.code,
            ownerId: ownerId,
            fileName: fileName,
            originalName: originalName,
            relativePath: relativePath,
            mimeType: Value(mimeType),
            fileSize: fileSize,
            documentType: Value(documentType),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );
    return FlyAttachment(
      id: id,
      ownerType: ownerType,
      ownerId: ownerId,
      fileName: fileName,
      originalName: originalName,
      relativePath: relativePath,
      mimeType: mimeType,
      fileSize: fileSize,
      documentType: documentType,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> changeDocumentType(String id, String documentType) =>
      (_db.update(_db.attachments)..where((row) => row.id.equals(id))).write(
        AttachmentsCompanion(
          documentType: Value(documentType),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> removeMetadata(String id) =>
      (_db.update(_db.attachments)..where((row) => row.id.equals(id))).write(
        AttachmentsCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  FlyAttachment _map(AttachmentRecord row) => FlyAttachment(
    id: row.id,
    ownerType: AttachmentOwnerTypeX.parse(row.ownerType),
    ownerId: row.ownerId,
    fileName: row.fileName,
    originalName: row.originalName,
    relativePath: row.relativePath,
    mimeType: row.mimeType,
    fileSize: row.fileSize,
    documentType: row.documentType,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );
}
