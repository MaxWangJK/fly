class DashboardEntry {
  const DashboardEntry({
    required this.id,
    required this.title,
    this.subtitle = '',
  });
  final String id;
  final String title;
  final String subtitle;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    this.hasBusinessData = true,
    required this.todayCustomers,
    required this.todayTasks,
    required this.importantUrgentTasks,
    required this.outstandingOrders,
    required this.outstandingByCurrency,
    required this.urgentOrders,
    required this.monthProfitRmb,
    required this.monthMissingRateCount,
  });

  final List<DashboardEntry> todayCustomers;
  final bool hasBusinessData;
  final List<DashboardEntry> todayTasks;
  final List<DashboardEntry> importantUrgentTasks;
  final List<DashboardEntry> outstandingOrders;
  final Map<String, int> outstandingByCurrency;
  final List<DashboardEntry> urgentOrders;
  final int monthProfitRmb;
  final int monthMissingRateCount;
}
