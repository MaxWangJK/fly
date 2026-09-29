abstract final class RelativeDateFormatter {
  static String createdAt(DateTime value, {DateTime? now, bool isZh = true}) {
    final local = value.toLocal();
    final reference = (now ?? DateTime.now()).toLocal();
    if (local.year != reference.year) {
      return isZh
          ? '${local.year}年${local.month}月${local.day}日'
          : '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    }
    return dateTime(local, now: reference, isZh: isZh);
  }

  static String dateTime(DateTime value, {DateTime? now, bool isZh = true}) {
    final reference = now ?? DateTime.now();
    final date = DateTime(value.year, value.month, value.day);
    final today = DateTime(reference.year, reference.month, reference.day);
    final time =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    if (date == today) return isZh ? '今天 $time' : 'Today $time';
    if (date == DateTime(today.year, today.month, today.day - 1)) {
      return isZh ? '昨天 $time' : 'Yesterday $time';
    }
    if (!isZh) {
      return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} $time';
    }
    if (value.year == reference.year) {
      return '${value.month}月${value.day}日 $time';
    }
    return '${value.year}年${value.month}月${value.day}日 $time';
  }

  static String lastFollowUp(
    DateTime? value, {
    DateTime? now,
    bool isZh = true,
  }) {
    if (value == null) return isZh ? '未跟进' : 'Not contacted';
    final reference = now ?? DateTime.now();
    final date = DateTime(value.year, value.month, value.day);
    final today = DateTime(reference.year, reference.month, reference.day);
    final difference = today.difference(date).inDays;
    if (difference <= 0) return isZh ? '今天' : 'Today';
    if (difference == 1) return isZh ? '昨天' : 'Yesterday';
    if (!isZh) {
      return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    if (value.year == reference.year) return '${value.month}月${value.day}日';
    return '${value.year}年${value.month}月${value.day}日';
  }
}
