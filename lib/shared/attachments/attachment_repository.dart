import 'attachment.dart';

abstract interface class AttachmentRepository {
  Stream<List<FlyAttachment>> watchOwner(
    AttachmentOwnerType ownerType,
    String ownerId,
  );

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
  });

  Future<void> changeDocumentType(String id, String documentType);
  Future<void> removeMetadata(String id);
}
