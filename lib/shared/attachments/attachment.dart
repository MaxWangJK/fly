enum AttachmentOwnerType { customer, order, payment, cost, task, library, note }

extension AttachmentOwnerTypeX on AttachmentOwnerType {
  String get code => name;

  String get folder => switch (this) {
    AttachmentOwnerType.customer => 'customers',
    AttachmentOwnerType.order => 'orders',
    AttachmentOwnerType.payment => 'payments',
    AttachmentOwnerType.cost => 'costs',
    AttachmentOwnerType.task => 'tasks',
    AttachmentOwnerType.library => 'library',
    AttachmentOwnerType.note => 'notes',
  };

  static AttachmentOwnerType parse(String value) =>
      AttachmentOwnerType.values.firstWhere(
        (type) => type.code == value,
        orElse: () => AttachmentOwnerType.order,
      );
}

class FlyAttachment {
  const FlyAttachment({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.fileName,
    required this.originalName,
    required this.relativePath,
    required this.mimeType,
    required this.fileSize,
    required this.documentType,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final AttachmentOwnerType ownerType;
  final String ownerId;
  final String fileName;
  final String originalName;
  final String relativePath;
  final String mimeType;
  final int fileSize;
  final String documentType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}
