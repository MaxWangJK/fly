import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/calendar/presentation/calendar_page.dart';
import '../features/matrix/presentation/matrix_page.dart';
import '../features/tasks/presentation/task_detail_panel.dart';
import '../features/tasks/presentation/task_list_page.dart';
import '../features/tasks/presentation/task_providers.dart';
import '../shared/design_system/app_theme.dart';
import 'shell/app_shell.dart';

final appRouterProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/today',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/today',
            builder: (context, state) => const TaskListPage(
              title: 'Today',
              collection: TaskCollection.today,
            ),
          ),
          GoRoute(
            path: '/inbox',
            builder: (context, state) => const TaskListPage(
              title: 'Inbox',
              collection: TaskCollection.inbox,
            ),
          ),
          GoRoute(
            path: '/upcoming',
            builder: (context, state) => const TaskListPage(
              title: 'Upcoming',
              collection: TaskCollection.upcoming,
            ),
          ),
          GoRoute(
            path: '/list/:id',
            builder: (context, state) => TaskListPage(
              title: 'List',
              collection: TaskCollection.custom,
              listId: state.pathParameters['id'],
            ),
          ),
          GoRoute(
            path: '/calendar',
            builder: (context, state) => const CalendarPage(),
          ),
          GoRoute(
            path: '/matrix',
            builder: (context, state) => const MatrixPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/task/:id',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Task details')),
          body: TaskDetailPanel(taskId: state.pathParameters['id']!),
        ),
      ),
    ],
  ),
);

class FlyApp extends ConsumerWidget {
  const FlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Fly',
      debugShowCheckedModeBanner: false,
      theme: FlyTheme.light(),
      darkTheme: FlyTheme.dark(),
      themeMode: themeMode,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
