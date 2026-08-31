enum TaskStatus { open, completed }

enum TaskPriority { none, low, medium, high }

enum MatrixQuadrant {
  importantUrgent,
  importantNotUrgent,
  notImportantUrgent,
  notImportantNotUrgent,
}

class FlyTask {
  const FlyTask({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.importance,
    required this.urgency,
    required this.isAllDay,
    required this.listId,
    required this.createdAt,
    required this.updatedAt,
    required this.sortOrder,
    required this.version,
    this.startDate,
    this.dueDate,
    this.completedAt,
    this.deletedAt,
    this.recurrenceRule,
    this.recurrenceEndAt,
  });

  final String id;
  final String title;
  final String description;
  final TaskStatus status;
  final TaskPriority priority;
  final bool importance;
  final bool urgency;
  final DateTime? startDate;
  final DateTime? dueDate;
  final bool isAllDay;
  final String listId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? deletedAt;
  final int sortOrder;
  final int version;
  final String? recurrenceRule;
  final DateTime? recurrenceEndAt;

  bool get isCompleted => status == TaskStatus.completed;
  bool get isDeleted => deletedAt != null;

  MatrixQuadrant get quadrant => switch ((importance, urgency)) {
    (true, true) => MatrixQuadrant.importantUrgent,
    (true, false) => MatrixQuadrant.importantNotUrgent,
    (false, true) => MatrixQuadrant.notImportantUrgent,
    (false, false) => MatrixQuadrant.notImportantNotUrgent,
  };

  FlyTask copyWith({
    String? id,
    String? title,
    String? description,
    TaskStatus? status,
    TaskPriority? priority,
    bool? importance,
    bool? urgency,
    Object? startDate = _unset,
    Object? dueDate = _unset,
    bool? isAllDay,
    String? listId,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = _unset,
    Object? deletedAt = _unset,
    int? sortOrder,
    int? version,
    Object? recurrenceRule = _unset,
    Object? recurrenceEndAt = _unset,
  }) {
    return FlyTask(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      importance: importance ?? this.importance,
      urgency: urgency ?? this.urgency,
      startDate: identical(startDate, _unset)
          ? this.startDate
          : startDate as DateTime?,
      dueDate: identical(dueDate, _unset) ? this.dueDate : dueDate as DateTime?,
      isAllDay: isAllDay ?? this.isAllDay,
      listId: listId ?? this.listId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      deletedAt: identical(deletedAt, _unset)
          ? this.deletedAt
          : deletedAt as DateTime?,
      sortOrder: sortOrder ?? this.sortOrder,
      version: version ?? this.version,
      recurrenceRule: identical(recurrenceRule, _unset)
          ? this.recurrenceRule
          : recurrenceRule as String?,
      recurrenceEndAt: identical(recurrenceEndAt, _unset)
          ? this.recurrenceEndAt
          : recurrenceEndAt as DateTime?,
    );
  }
}

class _Unset {
  const _Unset();
}

const _unset = _Unset();
