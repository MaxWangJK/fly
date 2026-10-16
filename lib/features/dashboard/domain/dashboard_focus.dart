enum DashboardFocusType {
  motto,
  mainMission,
  monthlyFocus,
  weeklyFocus,
  todayFocus,
}

class DashboardFocusSnapshot {
  const DashboardFocusSnapshot({
    this.motto = '',
    required this.mainMission,
    required this.monthlyFocus,
    required this.weeklyFocus,
    required this.todayFocus,
  });

  final String motto;
  final String mainMission;
  final String monthlyFocus;
  final String weeklyFocus;
  final String todayFocus;

  String content(DashboardFocusType type) => switch (type) {
    DashboardFocusType.motto => motto,
    DashboardFocusType.mainMission => mainMission,
    DashboardFocusType.monthlyFocus => monthlyFocus,
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
