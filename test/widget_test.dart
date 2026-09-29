import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/presentation/customer_sidebar.dart';
import 'package:fly/features/tasks/domain/task.dart';
import 'package:fly/features/tasks/domain/task_list.dart';
import 'package:fly/features/tasks/domain/task_repository.dart';
import 'package:fly/features/calendar/presentation/calendar_page.dart';
import 'package:fly/features/tasks/presentation/task_detail_panel.dart';
import 'package:fly/features/tasks/presentation/task_list_page.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/tasks/presentation/task_sidebar.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('task list renders Chinese quick add and empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inboxTasksProvider.overrideWith(
            (ref) => Stream<List<FlyTask>>.value(const []),
          ),
          taskListsProvider.overrideWith(
            (ref) => Stream<List<FlyTaskList>>.value(const []),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          supportedLocales: FlyLocalizations.supportedLocales,
          localizationsDelegates: [
            FlyLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: TaskListPage(collection: TaskCollection.inbox)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('\u6536\u96C6\u7BB1'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-add-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-add-button')), findsNothing);
    expect(find.text('\u73B0\u5728\u5F88\u6E05\u723D'), findsOneWidget);
  });

  testWidgets('completed view is localized and does not offer quick add', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          completedTasksProvider.overrideWith(
            (ref) => Stream<List<FlyTask>>.value(const []),
          ),
          taskListsProvider.overrideWith(
            (ref) => Stream<List<FlyTaskList>>.value(const []),
          ),
        ],
        child: const _LocalizedTestApp(
          child: TaskListPage(collection: TaskCollection.completed),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('\u5DF2\u5B8C\u6210'), findsOneWidget);
    expect(find.text('\u6DFB\u52A0\u4EFB\u52A1'), findsNothing);
    expect(
      find.text('\u8FD8\u6CA1\u6709\u5DF2\u5B8C\u6210\u4EFB\u52A1'),
      findsOneWidget,
    );
  });

  testWidgets('calendar quick add appears only after Add is chosen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthTasksProvider.overrideWith(
            (ref, month) => Stream<List<FlyTask>>.value(const []),
          ),
        ],
        child: const _LocalizedTestApp(child: CalendarPage()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.text('\u4E3A\u8FD9\u4E00\u5929\u6DFB\u52A0\u4EFB\u52A1\u2026'),
      findsNothing,
    );
    await tester.tap(find.byTooltip('\u6DFB\u52A0\u4EFB\u52A1'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text('\u4E3A\u8FD9\u4E00\u5929\u6DFB\u52A0\u4EFB\u52A1\u2026'),
      findsOneWidget,
    );
  });

  testWidgets('calendar popup creates a dated task on Enter', (tester) async {
    final repository = _RecordingTaskRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWithValue(repository),
          monthTasksProvider.overrideWith(
            (ref, month) => Stream<List<FlyTask>>.value(const []),
          ),
        ],
        child: const _LocalizedTestApp(child: CalendarPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('\u6DFB\u52A0\u4EFB\u52A1'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar-quick-add-dialog')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '\u5F39\u7A97\u4EFB\u52A1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('calendar-quick-add-dialog')),
      findsNothing,
    );
    expect(repository.created?.title, '\u5F39\u7A97\u4EFB\u52A1');
    expect(repository.created?.dueDate, isNotNull);
  });

  testWidgets('task detail uses compact choices and a two-click date range', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime.now();
    final task = _testTask('detail-task', 'Detail test', now);
    final repository = _RecordingTaskRepository();
    final inbox = FlyTaskList(
      id: 'inbox',
      name: 'Inbox',
      colorValue: 0xFF4D6BD8,
      createdAt: now,
      updatedAt: now,
      sortOrder: 0,
      version: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWithValue(repository),
          taskProvider.overrideWith((ref, id) => Stream<FlyTask?>.value(task)),
          taskListsProvider.overrideWith(
            (ref) => Stream<List<FlyTaskList>>.value([inbox]),
          ),
          taskTagsProvider.overrideWith(
            (ref, id) => Stream<List<String>>.value(const []),
          ),
          checklistProvider.overrideWith((ref, id) => Stream.value(const [])),
          reminderProvider.overrideWith((ref, id) => Stream.value(null)),
        ],
        child: _LocalizedTestApp(child: TaskDetailPanel(taskId: task.id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('\u4EFB\u52A1\u8BE6\u60C5'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.hintText == '\u6DFB\u52A0\u5907\u6CE8\u3001\u94FE\u63A5\u6216\u8865\u5145\u8BF4\u660E\u2026',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('\u9AD8'));
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final due = start.add(const Duration(days: 2));
    await tester.tap(
      find.byKey(
        ValueKey('quick-date-${start.year}-${start.month}-${start.day}'),
      ),
    );
    await tester.tap(
      find.byKey(ValueKey('quick-date-${due.year}-${due.month}-${due.day}')),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(repository.saved?.priority, TaskPriority.high);
    expect(repository.saved?.startDate, start);
    expect(repository.saved?.dueDate, due);
  });

  testWidgets(
    'primary modules start in Dashboard and show task sidebar only for tasks',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final database = AppDatabase(NativeDatabase.memory());
      await database.ensureBuiltInData();
      addTearDown(database.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            todayTasksProvider.overrideWith(
              (ref) => Stream<List<FlyTask>>.value(const []),
            ),
            taskListsProvider.overrideWith(
              (ref) => Stream<List<FlyTaskList>>.value(const []),
            ),
            monthTasksProvider.overrideWith(
              (ref, month) => Stream<List<FlyTask>>.value(const []),
            ),
            allTasksProvider.overrideWith(
              (ref) => Stream<List<FlyTask>>.value(const []),
            ),
          ],
          child: const FlyApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CustomerSidebar), findsNothing);
      expect(find.byType(TaskSidebar), findsNothing);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.byKey(const ValueKey('primary-tasks')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('primary-tasks')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TaskSidebar), findsOneWidget);
      expect(find.text('\u4ECA\u5929'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('primary-calendar')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CalendarPage), findsOneWidget);
      expect(find.byType(TaskSidebar), findsNothing);

      await tester.tap(find.byKey(const ValueKey('primary-matrix')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TaskSidebar), findsNothing);

      await tester.tap(find.byKey(const ValueKey('primary-tasks')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TaskSidebar), findsOneWidget);
      expect(find.text('\u4ECA\u5929'), findsWidgets);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(Duration.zero);
    },
  );
}

class _LocalizedTestApp extends StatelessWidget {
  const _LocalizedTestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: FlyTheme.light(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: FlyLocalizations.supportedLocales,
    localizationsDelegates: const [
      FlyLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

class _RecordingTaskRepository implements TaskRepository {
  FlyTask? created;
  FlyTask? saved;

  @override
  Future<FlyTask> createTask({
    required String title,
    String description = '',
    String listId = 'inbox',
    DateTime? dueDate,
    bool importance = false,
    bool urgency = false,
  }) async {
    final now = DateTime.now();
    final task = _testTask('created-task', title, now).copyWith(
      description: description,
      listId: listId,
      dueDate: dueDate,
      importance: importance,
      urgency: urgency,
    );
    created = task;
    return task;
  }

  @override
  Future<void> saveTask(FlyTask task) async {
    saved = task;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

FlyTask _testTask(String id, String title, DateTime now) => FlyTask(
  id: id,
  title: title,
  description: '',
  status: TaskStatus.open,
  priority: TaskPriority.none,
  importance: false,
  urgency: false,
  isAllDay: true,
  listId: 'inbox',
  createdAt: now,
  updatedAt: now,
  sortOrder: 0,
  version: 1,
);
