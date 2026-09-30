import 'package:drift/native.dart';
import 'package:fly/app/settings/navigation_settings.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/domain/task.dart';
import 'package:fly/features/dashboard/data/dashboard_service.dart';
import 'package:fly/shared/formatters/relative_date_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V8 Today local-day overlap, open endpoints, completion and Dashboard parity', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureBuiltInData();
    final repo = DriftTaskRepository(db);
    final today = DateTime(2026, 9, 7);
    Future<void> add(
      String name,
      DateTime? start,
      DateTime? due, {
      bool completed = false,
      bool completedAtOnly = false,
      bool deleted = false,
    }) async {
      final task = await repo.createTask(title: name);
      await repo.saveTask(
        task.copyWith(
          startDate: start,
          dueDate: due,
          status: completed ? TaskStatus.completed : TaskStatus.open,
          completedAt: completedAtOnly ? today : null,
          deletedAt: deleted ? today : null,
        ),
      );
    }

    await add('interval', DateTime(2026, 9, 6), DateTime(2026, 9, 8));
    await add('startToday', today, null);
    await add('dueToday', null, today);
    await add('startYesterday', DateTime(2026, 9, 6), null);
    await add('overdue', null, DateTime(2026, 9, 6));
    await add('undated', null, null);
    await add('tomorrow', DateTime(2026, 9, 8), null);
    await add(
      'completed',
      DateTime(2026, 9, 6),
      DateTime(2026, 9, 8),
      completed: true,
    );
    await add('completedAt', today, null, completedAtOnly: true);
    await add('deleted', today, null, deleted: true);
    await add('midnightEnd', DateTime(2026, 9, 6), today);
    await add(
      'beforeMidnight',
      null,
      today.subtract(const Duration(seconds: 1)),
    );
    await add('lastSecond', null, DateTime(2026, 9, 7, 23, 59, 59));
    await add('nextMidnight', null, DateTime(2026, 9, 8));
    await add(
      'utcSameInstant',
      today.toUtc(),
      DateTime(2026, 9, 7, 23).toUtc(),
    );
    final rows = await repo.watchTodayTasks(today).first;
    expect(
      rows.map((t) => t.title),
      unorderedEquals([
        'interval',
        'startToday',
        'dueToday',
        'midnightEnd',
        'lastSecond',
        'utcSameInstant',
      ]),
    );
    final dashboard = await DashboardService(db, now: () => today).load();
    expect(
      dashboard.todayTasks.map((t) => t.id),
      unorderedEquals(rows.map((t) => t.id)),
    );
  });

  test('V8 navigation defaults, persistence, resolver and business data preservation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureBuiltInData();
    final customer = await DriftCustomerRepository(db)
        .createCustomer(name: 'Jack');
    final order = await DriftOrderRepository(db)
        .createOrder(customerId: customer.id, orderNumber: '001');
    final nav = NavigationSettingsController(db);
    await nav.ready;
    expect(nav.value.dashboardVisible, isFalse);
    expect(nav.value.crmVisible, isTrue);
    for (final dashboard in [true, false]) {
      for (final crm in [true, false]) {
        await nav.update(
          NavigationSettings(dashboardVisible: dashboard, crmVisible: crm),
        );
        final restored = NavigationSettingsController(db);
        await restored.ready;
        expect(restored.value.dashboardVisible, dashboard);
        expect(restored.value.crmVisible, crm);
        expect(
          StartupWorkspaceResolver.resolve(restored.value),
          dashboard
              ? '/dashboard'
              : crm
              ? '/customers/today'
              : '/tasks/today',
        );
        expect(
          StartupWorkspaceResolver.allowed('/orders', restored.value),
          crm,
        );
        expect(
          StartupWorkspaceResolver.allowed('/customers/today', restored.value),
          crm,
        );
        expect(
          StartupWorkspaceResolver.allowed('/tasks/today', restored.value),
          isTrue,
        );
        restored.dispose();
      }
    }
    await nav.update(const NavigationSettings());
    expect(
      (await db.select(db.customers).get()).any(
        (v) => v.id == customer.id && v.deletedAt == null,
      ),
      isTrue,
    );
    expect(
      (await db.select(db.orders).get()).any(
        (v) => v.id == order.id && v.deletedAt == null,
      ),
      isTrue,
    );
    nav.dispose();
  });

  test('V8 Matrix creation labels are local and concise', () {
    final now = DateTime(2026, 9, 7, 16);
    expect(
      RelativeDateFormatter.createdAt(DateTime(2026, 9, 7, 14, 30), now: now),
      '今天 14:30',
    );
    expect(
      RelativeDateFormatter.createdAt(DateTime(2026, 9, 6, 9, 30), now: now),
      '昨天 09:30',
    );
    expect(
      RelativeDateFormatter.createdAt(DateTime(2026, 8, 30, 16, 20), now: now),
      '8月30日 16:20',
    );
    expect(
      RelativeDateFormatter.createdAt(DateTime(2025, 12, 20), now: now),
      '2025年12月20日',
    );
    expect(
      RelativeDateFormatter.createdAt(
        DateTime(2026, 9, 7, 14, 30).toUtc(),
        now: now,
      ),
      '今天 14:30',
    );
  });
}
