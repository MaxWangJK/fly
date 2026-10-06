enum DashboardFocusType { mainMission, weeklyFocus, todayFocus }

class DashboardFocusSnapshot {
  const DashboardFocusSnapshot({
    required this.mainMission,
    required this.weeklyFocus,
    required this.todayFocus,
  });

  final String mainMission;
  final String weeklyFocus;
  final String todayFocus;

  String content(DashboardFocusType type) => switch (type) {
    DashboardFocusType.mainMission => mainMission,
    DashboardFocusType.weeklyFocus => weeklyFocus,
    DashboardFocusType.todayFocus => todayFocus,
  };
}

class DashboardFocusHistoryEntry {
  const DashboardFocusHistoryEntry({
    required this.id,
    required this.type,
    required this.content,
    required this.effectiveDate,
    required this.recordedAt,
  });

  final String id;
  final DashboardFocusType type;
  final String content;
  final DateTime effectiveDate;
  final DateTime recordedAt;
}
