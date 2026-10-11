import 'package:flutter/material.dart';

import '../config/feature_flags.dart';
import '../features/sync/presentation/sync_runtime.dart';
import '../shared/licensing/local_license_gate.dart';

import '../features/reviews/presentation/daily_review_page.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/calendar/presentation/calendar_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/customers/domain/customer.dart';
import '../features/customers/presentation/customer_list_page.dart';
import '../features/matrix/presentation/matrix_page.dart';
import '../features/files/presentation/files_workspace.dart';
import '../features/knowledge/presentation/knowledge_workspace.dart';
import '../features/notes/presentation/notes_workspace.dart';
import '../features/orders/domain/order.dart';
import '../features/orders/presentation/order_list_page.dart';
import '../features/tasks/presentation/task_detail_panel.dart';
import '../features/tasks/presentation/task_focus_page.dart';
import '../features/tasks/presentation/task_list_page.dart';
import '../features/tasks/presentation/task_providers.dart';
import '../features/tools/container_loading/presentation/workspace/container_loading_page.dart';
import '../l10n/fly_localizations.dart';
import '../shared/design_system/app_theme.dart';
import 'shell/app_shell.dart';
import 'settings/navigation_settings.dart';

const _initialLocation = String.fromEnvironment(
  'FLY_INITIAL_ROUTE',
  defaultValue: '/',
);

final appRouterProvider = Provider<GoRouter>((ref) {
  final navigation = ref.read(navigationSettingsProvider);
  final router = GoRouter(
    initialLocation: '/startup',
    refreshListenable: navigation,
    redirect: (context, state) {
      if (!navigation.loaded) {
        return state.uri.path == '/startup' ? null : '/startup';
      }
      final path = state.uri.path;
      if (path == '/startup') {
        return _initialLocation != '/' &&
                StartupWorkspaceResolver.allowed(
                  _initialLocation,
                  navigation.value,
                )
            ? _initialLocation
            : StartupWorkspaceResolver.resolve(navigation.value);
      }
      if (path == '/' ||
          !StartupWorkspaceResolver.allowed(path, navigation.value)) {
        return StartupWorkspaceResolver.resolve(navigation.value);
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/startup',
        builder: (context, state) => const Scaffold(
          body: Center(child: CircularProgressIndicator.adaptive()),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/files',
            builder: (context, state) => FilesWorkspace(
              key: ValueKey(state.uri.queryParameters['id']),
              initialFileId: state.uri.queryParameters['id'],
            ),
          ),
          GoRoute(
            path: '/notes',
            builder: (context, state) => NotesWorkspace(
              key: ValueKey(state.uri.queryParameters['id']),
              initialNoteId: state.uri.queryParameters['id'],
            ),
            redirect: (context, state) {
              if (!enableKnowledgeHub) return null;
              final id = state.uri.queryParameters['id'];
              final parameters = <String, String>{'view': 'notes'};
              if (id != null) parameters['id'] = id;
              return Uri(
                path: '/knowledge',
                queryParameters: parameters,
              ).toString();
            },
          ),
          GoRoute(
            path: '/knowledge',
            redirect: (context, state) => enableKnowledgeHub
                ? null
                : Uri(
                    path: '/notes',
                    queryParameters: {
                      if (state.uri.queryParameters['id'] != null)
                        'id': state.uri.queryParameters['id']!,
                    },
                  ).toString(),
            builder: (context, state) => KnowledgeWorkspace(
              key: ValueKey(state.uri.toString()),
              initialArticleId: state.uri.queryParameters['article'],
              initialNoteId: state.uri.queryParameters['id'],
              showNotes: state.uri.queryParameters['view'] == 'notes',
            ),
          ),
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/customers/today',
            builder: (context, state) =>
                const CustomerListPage(projection: CustomerProjection.today),
          ),
          GoRoute(
            path: '/customers/next7days',
            builder: (context, state) => const CustomerListPage(
              projection: CustomerProjection.next7Days,
            ),
          ),
          GoRoute(
            path: '/customers/inbox',
            builder: (context, state) =>
                const CustomerListPage(projection: CustomerProjection.inbox),
          ),
          GoRoute(
            path: '/customers/all',
            builder: (context, state) =>
                const CustomerListPage(projection: CustomerProjection.all),
          ),
          GoRoute(
            path: '/customers/deleted',
            builder: (context, state) =>
                const CustomerListPage(projection: CustomerProjection.deleted),
          ),
          GoRoute(
            path: '/customers/category/:id',
            builder: (context, state) => CustomerListPage(
              projection: CustomerProjection.category,
              categoryId: state.pathParameters['id'],
            ),
          ),
          GoRoute(
            path: '/orders/all',
            builder: (context, state) =>
                const OrderListPage(projection: OrderProjection.all),
          ),
          GoRoute(
            path: '/orders/important',
            builder: (context, state) =>
                const OrderListPage(projection: OrderProjection.important),
          ),
          GoRoute(
            path: '/orders/urgent',
            builder: (context, state) =>
                const OrderListPage(projection: OrderProjection.urgent),
          ),
          GoRoute(
            path: '/orders/outstanding',
            builder: (context, state) =>
                const OrderListPage(projection: OrderProjection.outstanding),
          ),
          GoRoute(
            path: '/orders/normal',
            builder: (context, state) =>
                const OrderListPage(projection: OrderProjection.normal),
          ),
          GoRoute(
            path: '/orders/deleted',
            builder: (context, state) =>
                const OrderListPage(projection: OrderProjection.deleted),
          ),
          GoRoute(
            path: '/orders/tag/:id',
            builder: (context, state) => OrderListPage(
              projection: OrderProjection.tag,
              tagId: state.pathParameters['id'],
            ),
          ),
          GoRoute(
            path: '/tasks/today',
            builder: (context, state) =>
                const TaskListPage(collection: TaskCollection.today),
          ),
          GoRoute(
            path: '/tasks/review',
            builder: (context, state) => const DailyReviewPage(),
          ),
          GoRoute(
            path: '/tasks/focus',
            builder: (context, state) => const TaskFocusPage(),
          ),
          GoRoute(
            path: '/tasks/inbox',
            builder: (context, state) =>
                const TaskListPage(collection: TaskCollection.inbox),
          ),
          GoRoute(
            path: '/tasks/next7days',
            builder: (context, state) =>
                const TaskListPage(collection: TaskCollection.upcoming),
          ),
          GoRoute(
            path: '/tasks/completed',
            builder: (context, state) =>
                const TaskListPage(collection: TaskCollection.completed),
          ),
          GoRoute(
            path: '/tasks/trash',
            builder: (context, state) =>
                const TaskListPage(collection: TaskCollection.trash),
          ),
          GoRoute(
            path: '/tasks/list/:id',
            builder: (context, state) => TaskListPage(
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
          GoRoute(
            path: '/tools/container-loading',
            builder: (context, state) => const ContainerLoadingPage(),
          ),
        ],
      ),
      GoRoute(path: '/', redirect: (context, state) => '/customers/today'),
      GoRoute(path: '/today', redirect: (context, state) => '/tasks/today'),
      GoRoute(
        path: '/upcoming',
        redirect: (context, state) => '/tasks/next7days',
      ),
      GoRoute(path: '/inbox', redirect: (context, state) => '/tasks/inbox'),
      GoRoute(
        path: '/completed',
        redirect: (context, state) => '/tasks/completed',
      ),
      GoRoute(path: '/trash', redirect: (context, state) => '/tasks/trash'),
      GoRoute(
        path: '/list/:id',
        redirect: (context, state) =>
            '/tasks/list/${state.pathParameters['id']}',
      ),
      GoRoute(
        path: '/task/:id',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(context.l10n.t('details'))),
          body: TaskDetailPanel(taskId: state.pathParameters['id']!),
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class FlyApp extends ConsumerWidget {
  const FlyApp({this.startupBackupFailed = false, super.key});

  final bool startupBackupFailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(flyPaletteProvider);
    return MaterialApp.router(
      title: 'Fly',
      debugShowCheckedModeBanner: false,
      theme: FlyTheme.light(palette),
      darkTheme: FlyTheme.dark(palette),
      themeMode: ref.watch(themeModeProvider),
      locale: ref.watch(localeProvider),
      supportedLocales: FlyLocalizations.supportedLocales,
      localizationsDelegates: const [
        FlyLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        final content = enableLocalLicense
            ? LocalLicenseGate(child: child ?? const SizedBox.shrink())
            : child ?? const SizedBox.shrink();
        return SyncRuntime(
          child: startupBackupFailed
              ? _StartupBackupWarning(child: content)
              : content,
        );
      },
    );
  }
}

class _StartupBackupWarning extends StatefulWidget {
  const _StartupBackupWarning({required this.child});

  final Widget child;

  @override
  State<_StartupBackupWarning> createState() => _StartupBackupWarningState();
}

class _StartupBackupWarningState extends State<_StartupBackupWarning> {
  bool _visible = true;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (_visible)
        Positioned(
          top: 12,
          right: 12,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.errorContainer,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text('今日自动备份失败；数据仍可使用。请到设置检查备份目录并手动备份。'),
                    ),
                    IconButton(
                      tooltip: '关闭提醒',
                      onPressed: () => setState(() => _visible = false),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
