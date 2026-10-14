class FlyTaskList {
  const FlyTaskList({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
    required this.sortOrder,
    required this.version,
    this.deletedAt,
    this.parentId,
  });

  final String? parentId;
  final String id;
  final String name;
  final int colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int sortOrder;
  final int version;
}
