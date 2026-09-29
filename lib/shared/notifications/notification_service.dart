import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

class ReminderSettings {
  const ReminderSettings({
    this.enabled = true,
    this.offsetMinutes = const {10, 60, 1440},
    this.reviewEnabled = false,
    this.reviewMinute = 1200,
  });

  final bool enabled;
  final Set<int> offsetMinutes;
  final bool reviewEnabled;
  final int reviewMinute;

  ReminderSettings copyWith({
    bool? enabled,
    Set<int>? offsetMinutes,
    bool? reviewEnabled,
    int? reviewMinute,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    reviewEnabled: reviewEnabled ?? this.reviewEnabled,
    reviewMinute: reviewMinute ?? this.reviewMinute,
  );
}

abstract interface class NotificationGateway {
  Future<void> initialize();
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });
}

final notificationTapStream = StreamController<String>.broadcast();

class WindowsNotificationGateway implements NotificationGateway {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;

  @override
  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (!Platform.isWindows) return;
    const settings = InitializationSettings(
      windows: WindowsInitializationSettings(
        appName: 'Fly',
        appUserModelId: 'Fly.Desktop.Productivity.1',
        guid: 'f8a1a728-3e45-4d44-98b5-c7b9bc6f24d1',
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          notificationTapStream.add(payload);
        }
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) &&
        payload != null &&
        payload.isNotEmpty) {
      notificationTapStream.add(payload);
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    await initialize();
    if (!Platform.isWindows) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: const NotificationDetails(
        windows: WindowsNotificationDetails(
          duration: WindowsNotificationDuration.short,
        ),
      ),
    );
  }
}

class NotificationService {
  NotificationService(
    this._db,
    this._gateway, {
    DateTime Function()? now,
    this._uuid = const Uuid(),
  }) : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final NotificationGateway _gateway;
  final DateTime Function() _now;
  final Uuid _uuid;

  static const _enabledKey = 'notifications.enabled';
  static const _offsetsKey = 'notifications.offsetMinutes';
  static const _reviewEnabledKey = 'notifications.reviewEnabled';
  static const _reviewMinuteKey = 'notifications.reviewMinute';

  Future<ReminderSettings> loadSettings() async {
    final rows =
        await (_db.select(_db.appSettings)..where(
              (row) => row.key.isIn([
                _enabledKey,
                _offsetsKey,
                _reviewEnabledKey,
                _reviewMinuteKey,
              ]),
            ))
            .get();
    final values = {for (final row in rows) row.key: row.value};
    final offsets = (values[_offsetsKey] ?? '10,60,1440')
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    return ReminderSettings(
      enabled: values[_enabledKey] != 'false',
      offsetMinutes: offsets.isEmpty ? const {10, 60, 1440} : offsets,
      reviewEnabled: values[_reviewEnabledKey] == 'true',
      reviewMinute: (int.tryParse(values[_reviewMinuteKey] ?? '') ?? 1200)
          .clamp(0, 1439),
    );
  }

  Future<void> saveSettings(ReminderSettings settings) async {
    final now = _now();
    final offsets = settings.offsetMinutes.toList()..sort();
    for (final entry in {
      _enabledKey: settings.enabled.toString(),
      _offsetsKey: offsets.join(','),
      _reviewEnabledKey: settings.reviewEnabled.toString(),
      _reviewMinuteKey: settings.reviewMinute.clamp(0, 1439).toString(),
    }.entries) {
      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: entry.key,
              value: entry.value,
              updatedAt: now,
            ),
          );
    }
  }

  Future<int> checkAndDeliver() async {
    final settings = await loadSettings();
    if (!settings.enabled) return 0;
    await _gateway.initialize();
    final now = _now();
    final candidates = <_NotificationCandidate>[];
    final locale = await (_db.select(
      _db.appSettings,
    )..where((r) => r.key.equals('locale'))).getSingleOrNull();
    final english = locale?.value.startsWith('en') ?? false;
    if (settings.reviewEnabled) {
      final day =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      candidates.add(
        _NotificationCandidate(
          entityType: 'review',
          entityId: day,
          scheduledTime: DateTime(
            now.year,
            now.month,
            now.day,
            settings.reviewMinute ~/ 60,
            settings.reviewMinute % 60,
          ),
          title: english ? 'Daily review' : '今日复盘',
          body: english ? 'Reflect and plan tomorrow' : '回顾今天，安排明日行动',
        ),
      );
    }

    final taskRows =
        await (_db.select(_db.reminders).join([
              innerJoin(
                _db.tasks,
                _db.tasks.id.equalsExp(_db.reminders.taskId),
              ),
            ])..where(
              _db.reminders.deletedAt.isNull() &
                  _db.reminders.isEnabled.equals(true) &
                  _db.tasks.deletedAt.isNull() &
                  _db.tasks.status.equals('open'),
            ))
            .get();
    for (final row in taskRows) {
      final reminder = row.readTable(_db.reminders);
      final task = row.readTable(_db.tasks);
      candidates.add(
        _NotificationCandidate(
          entityType: 'task',
          entityId: task.id,
          scheduledTime: reminder.remindAt,
          title: english ? 'Task reminder' : '任务提醒',
          body:
              '${task.title} ${_relativeDue(reminder.remindAt, now, english: english)}',
        ),
      );
    }

    final customers =
        await (_db.select(_db.customers)..where(
              (row) =>
                  row.deletedAt.isNull() & row.nextFollowUpDate.isNotNull(),
            ))
            .get();
    for (final customer in customers) {
      final due = customer.nextFollowUpDate!;
      final eventTime = DateTime(due.year, due.month, due.day, 9);
      for (final offset in settings.offsetMinutes) {
        candidates.add(
          _NotificationCandidate(
            entityType: 'customer',
            entityId: customer.id,
            scheduledTime: eventTime.subtract(Duration(minutes: offset)),
            title: english ? 'Customer follow-up' : '客户跟进',
            body: english
                ? '${customer.name} — follow up ${_relativeDue(eventTime, now, english: true)}'
                : '${customer.name} ${_relativeDue(eventTime, now)}需要跟进',
          ),
        );
      }
    }

    final orders =
        await (_db.select(_db.orders)..where(
              (row) => row.deletedAt.isNull() & row.deliveryDate.isNotNull(),
            ))
            .get();
    for (final order in orders) {
      final due = order.deliveryDate!;
      final eventTime = DateTime(due.year, due.month, due.day, 9);
      for (final offset in settings.offsetMinutes) {
        candidates.add(
          _NotificationCandidate(
            entityType: 'order',
            entityId: order.id,
            scheduledTime: eventTime.subtract(Duration(minutes: offset)),
            title: english ? 'Order delivery' : '订单交期',
            body: english
                ? '${order.orderNumber} — delivery ${_relativeDue(eventTime, now, english: true)}'
                : '${order.orderNumber} ${_relativeDue(eventTime, now)}交货',
          ),
        );
      }
    }

    // If Fly was closed across several configured offsets, emit only the most
    // recent due reminder for an entity on the next check. This keeps catch-up
    // useful without showing three stale toasts at once. A later offset can
    // still be delivered normally when it becomes due.
    final latestDueByEntity = <String, _NotificationCandidate>{};
    for (final candidate in candidates) {
      if (candidate.scheduledTime.isAfter(now) ||
          candidate.scheduledTime.isBefore(
            now.subtract(const Duration(days: 2)),
          )) {
        continue;
      }
      final key = '${candidate.entityType}\u0000${candidate.entityId}';
      final previous = latestDueByEntity[key];
      if (previous == null ||
          candidate.scheduledTime.isAfter(previous.scheduledTime)) {
        latestDueByEntity[key] = candidate;
      }
    }

    var delivered = 0;
    for (final candidate in latestDueByEntity.values) {
      final existing =
          await (_db.select(_db.notificationDeliveryLogs)..where(
                (row) =>
                    row.entityType.equals(candidate.entityType) &
                    row.entityId.equals(candidate.entityId) &
                    (candidate.entityType == 'review'
                        ? const Constant(true)
                        : row.scheduledTime.equals(candidate.scheduledTime)),
              ))
              .getSingleOrNull();
      if (existing != null) continue;
      await _gateway.show(
        id:
            Object.hash(
              candidate.entityType,
              candidate.entityId,
              candidate.scheduledTime,
            ) &
            0x7fffffff,
        title: candidate.title,
        body: candidate.body,
        payload: '${candidate.entityType}:${candidate.entityId}',
      );
      await _db
          .into(_db.notificationDeliveryLogs)
          .insert(
            NotificationDeliveryLogsCompanion.insert(
              id: _uuid.v7(),
              entityType: candidate.entityType,
              entityId: candidate.entityId,
              scheduledTime: candidate.scheduledTime,
              deliveredAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      delivered += 1;
    }
    return delivered;
  }

  String _relativeDue(DateTime due, DateTime now, {bool english = false}) {
    final dueDay = DateTime(due.year, due.month, due.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = dueDay.difference(today).inDays;
    return switch (days) {
      0 => english ? 'today' : '今天',
      1 => english ? 'tomorrow' : '明天',
      -1 => english ? 'yesterday' : '昨天',
      _ =>
        english
            ? '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}'
            : '${due.month}月${due.day}日',
    };
  }
}

class _NotificationCandidate {
  const _NotificationCandidate({
    required this.entityType,
    required this.entityId,
    required this.scheduledTime,
    required this.title,
    required this.body,
  });

  final String entityType;
  final String entityId;
  final DateTime scheduledTime;
  final String title;
  final String body;
}
