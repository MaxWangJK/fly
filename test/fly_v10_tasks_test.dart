import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fly/app/app.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/domain/task_date_range.dart';
import 'package:fly/features/tasks/presentation/widgets/task_components.dart';

void main() {
  testWidgets(
    'V10 Today groups overdue newest-first and confirms batch postponement',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      final repo = DriftTaskRepository(db);
      final day = DateTime(2026, 9, 8);
      await tester.runAsync(() async {
        await db.ensureBuiltInData();
        await repo.createTask(title: '今天处理', dueDate: day);
        await repo.createTask(title: '较早过期', dueDate: DateTime(2026, 9, 5));
        await repo.createTask(title: '最近过期', dueDate: DateTime(2026, 9, 7));
      });
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localTodayProvider.overrideWith((ref) => day),
        ],
      );
      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const FlyApp()),
      );
      await settle();
      container.read(appRouterProvider).go('/tasks/today');
      await settle();
      expect(
        tester.getTopLeft(find.text('今天处理').first).dy,
        lessThan(tester.getTopLeft(find.text('最近过期')).dy),
      );
      expect(
        tester.getTopLeft(find.text('最近过期')).dy,
        lessThan(tester.getTopLeft(find.text('较早过期')).dy),
      );
      await tester.tap(find.text('全部顺延到今天'));
      await settle();
      expect(find.text('将 2 个任务顺延到今天？开始日期保持不变。'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await settle();
      expect(find.text('全部顺延到今天'), findsNothing);
      expect(find.byType(ReorderableDragStartListener), findsNWidgets(3));
      await tester.runAsync(
        () async => expect((await repo.watchTodayTasks(day).first).length, 3),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await settle();
      addTearDown(db.close);
    },
  );
  test('V10 inclusive range is shared by Today and calendar, without duplicate rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final repo = DriftTaskRepository(db);
      var task = await repo.createTask(
        title: '跨日',
        dueDate: DateTime(2026, 9, 10),
      );
      task = task.copyWith(startDate: DateTime(2026, 9, 7));
      await repo.saveTask(task);
      for (var day = 7; day <= 10; day++) {
        expect(TaskDateRange.contains(task, DateTime(2026, 9, day)), true);
        expect(
          (await repo.watchTodayTasks(DateTime(2026, 9, day)).first).single.id,
          task.id,
        );
        expect(
          (await repo
                  .watchTasksForRange(
                    DateTime(2026, 9, day),
                    DateTime(2026, 9, day + 1),
                  )
                  .first)
              .single
              .id,
          task.id,
        );
      }
      expect((await repo.watchAllTasks().first).length, 1);
      expect(TaskDateRange.isOverdue(task, DateTime(2026, 9, 11)), true);
      await repo.postponeOverdueTasks([task.id], DateTime(2026, 9, 11));
      final moved = (await repo.watchTask(task.id).first)!;
      expect(moved.startDate, task.startDate);
      expect(moved.dueDate, DateTime(2026, 9, 11));
      await repo.setCompleted(task.id, completed: true);
      final completed = (await repo.watchTask(task.id).first)!;
      expect(TaskDateRange.isOverdue(completed, DateTime(2026, 9, 12)), false);
      expect(await repo.watchTodayTasks(DateTime(2026, 9, 11)).first, isEmpty);
      // Existing calendar completed visibility is retained.
      expect(
        (await repo
                .watchTasksForRange(DateTime(2026, 9, 7), DateTime(2026, 9, 12))
                .first)
            .single
            .isCompleted,
        true,
      );
    } finally {
      await db.close();
    }
  });

  test('V10 single-ended dates and cross-month intersection', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final repo = DriftTaskRepository(db);
      final startOnly = await repo.createTask(title: '开始日');
      await repo.saveTask(
        startOnly.copyWith(startDate: DateTime(2026, 9, 8, 14)),
      );
      final dueOnly = await repo.createTask(
        title: '截止日',
        dueDate: DateTime(2026, 9, 8, 18),
      );
      expect(
        (await repo.watchTodayTasks(DateTime(2026, 9, 8)).first).length,
        2,
      );
      expect(await repo.watchTodayTasks(DateTime(2026, 9, 9)).first, isEmpty);
      expect(TaskDateRange.isOverdue(dueOnly, DateTime(2026, 9, 9)), true);
      final spanning = await repo.createTask(
        title: '跨月',
        dueDate: DateTime(2026, 10, 3),
      );
      await repo.saveTask(spanning.copyWith(startDate: DateTime(2026, 8, 30)));
      expect(
        (await repo
                .watchTasksForRange(DateTime(2026, 9, 1), DateTime(2026, 9, 2))
                .first)
            .single
            .id,
        spanning.id,
      );
      await repo.deleteTask(spanning.id);
      expect(
        await repo
            .watchTasksForRange(DateTime(2026, 9, 1), DateTime(2026, 9, 2))
            .first,
        isEmpty,
      );
    } finally {
      await db.close();
    }
  });

  testWidgets(
    'V10 matrix checkbox title and metadata share a horizontal center',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = DriftTaskRepository(db);
      final task = await tester.runAsync(() async {
        await db.ensureBuiltInData();
        return repo.createTask(title: '矩阵对齐');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: FlyTaskRowSurface(
                task: task!,
                compact: true,
                metadata: '今天 09:20',
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      final titleY = tester.getCenter(find.text('矩阵对齐')).dy;
      expect(
        (tester.getCenter(find.text('今天 09:20')).dy - titleY).abs(),
        lessThan(1),
      );
      expect(
        (tester.getCenter(find.byType(Checkbox)).dy - titleY).abs(),
        lessThan(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      addTearDown(db.close);
    },
  );
}
