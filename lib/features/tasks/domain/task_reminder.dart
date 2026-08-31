class FlyReminder {
  const FlyReminder({
    required this.id,
    required this.taskId,
    required this.remindAt,
    required this.isEnabled,
  });

  final String id;
  final String taskId;
  final DateTime remindAt;
  final bool isEnabled;
}
