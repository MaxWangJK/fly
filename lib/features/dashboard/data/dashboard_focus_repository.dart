import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/dashboard_focus.dart';

class DashboardFocusRepository {
  const DashboardFocusRepository(this.db);

  final AppDatabase db;

  static String dayKey(DateTime day) {
    final local = day.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  Future<DashboardFocusSnapshot> read(DateTime day) async {
    final rows = await db.select(db.dashboardFocuses).get();
    final values = {for (final row in rows) row.focusType: row.content};
    final daily = await (db.select(
      db.dashboardDailyFocuses,
    )..where((row) => row.dayKey.equals(dayKey(day)))).getSingleOrNull();
    return DashboardFocusSnapshot(
      motto: values[DashboardFocusType.motto.name] ?? '',
      mainMission: values[DashboardFocusType.mainMission.name] ?? '',
      monthlyFocus: values[DashboardFocusType.monthlyFocus.name] ?? '',
      weeklyFocus: values[DashboardFocusType.weeklyFocus.name] ?? '',
      todayFocus: daily?.content ?? '',
    );
  }

  /// Commits one completed edit. Old non-empty content becomes history only
  /// when the normalized value really changed; drafts never reach this layer.
  Future<bool> save({
    required DashboardFocusType type,
    required String content,
    required DateTime day,
  }) async {
    final next = content.trim();
    if (next.runes.length > 800) {
      throw ArgumentError.value(content, 'content', 'Maximum 800 characters');
    }
    return db.transaction(() async {
      final now = DateTime.now();
      if (type == DashboardFocusType.todayFocus) {
        final key = dayKey(day);
        final current = await (db.select(
          db.dashboardDailyFocuses,
        )..where((row) => row.dayKey.equals(key))).getSingleOrNull();
        if (current?.content == next || (current == null && next.isEmpty)) {
          return false;
        }
        if (current != null && current.content.isNotEmpty) {
          await _recordHistory(
            type: type,
            content: current.content,
            effectiveDate: DateTime(day.year, day.month, day.day),
            now: now,
          );
        }
        await db
            .into(db.dashboardDailyFocuses)
            .insertOnConflictUpdate(
              DashboardDailyFocusesCompanion.insert(
                dayKey: key,
                content: next,
                createdAt: current?.createdAt ?? now,
                updatedAt: now,
              ),
            );
        return true;
      }

      final current = await (db.select(
        db.dashboardFocuses,
      )..where((row) => row.focusType.equals(type.name))).getSingleOrNull();
      if (current?.content == next || (current == null && next.isEmpty)) {
        return false;
      }
      if (current != null && current.content.isNotEmpty) {
        await _recordHistory(
          type: type,
          content: current.content,
          effectiveDate: current.updatedAt,
          now: now,
        );
      }
      await db
          .into(db.dashboardFocuses)
          .insertOnConflictUpdate(
            DashboardFocusesCompanion.insert(
              id: type.name,
              focusType: type.name,
              content: next,
              createdAt: current?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      return true;
    });
  }

  Future<void> _recordHistory({
    required DashboardFocusType type,
    required String content,
    required DateTime effectiveDate,
    required DateTime now,
  }) => db
      .into(db.dashboardFocusHistories)
      .insert(
        DashboardFocusHistoriesCompanion.insert(
          id: const Uuid().v4(),
          focusType: type.name,
          content: content,
          effectiveDate: effectiveDate,
          createdAt: now,
        ),
      );

  Future<List<DashboardFocusHistoryEntry>> history() async {
    final versions = await db.select(db.dashboardFocusHistories).get();
    final daily = await db.select(db.dashboardDailyFocuses).get();
    final entries = [
      for (final row in versions)
        if (row.content.isNotEmpty)
          DashboardFocusHistoryEntry(
            id: row.id,
            type: DashboardFocusType.values.byName(row.focusType),
            content: row.content,
            effectiveDate: row.effectiveDate,
            recordedAt: row.createdAt,
          ),
      for (final row in daily)
        if (row.content.isNotEmpty)
          DashboardFocusHistoryEntry(
            id: 'day-${row.dayKey}',
            type: DashboardFocusType.todayFocus,
            content: row.content,
            effectiveDate: DateTime.parse(row.dayKey),
            recordedAt: row.updatedAt,
          ),
    ];
    entries.sort((a, b) {
      final byDate = b.effectiveDate.compareTo(a.effectiveDate);
      return byDate != 0 ? byDate : b.recordedAt.compareTo(a.recordedAt);
    });
    return entries;
  }
}
