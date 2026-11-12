import 'package:flutter/material.dart';

import '../../config/feature_flags.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/local_profile_avatar.dart';
import '../../features/sync/presentation/mobile_sync_button.dart';
import '../../features/customers/presentation/customer_detail_panel.dart';
import '../../features/customers/presentation/customer_extension_panel.dart';
import '../../features/customers/presentation/customer_providers.dart';
import '../../features/customers/presentation/customer_sidebar.dart';
import '../../features/orders/presentation/order_detail_panel.dart';
import '../../features/orders/presentation/order_providers.dart';
import '../../features/orders/presentation/order_sidebar.dart';
import '../../features/tasks/presentation/task_detail_panel.dart';
import '../../features/tasks/presentation/task_providers.dart';
import '../../features/notes/presentation/note_close_guard.dart';
import '../../features/tasks/presentation/task_sidebar.dart';
import '../../features/tools/presentation/tools_sidebar.dart';
import '../../l10n/fly_localizations.dart';
import '../../shared/design_system/design_tokens.dart';
import '../../shared/design_system/responsive_layout.dart';
import '../../shared/search/global_search_palette.dart';
import '../../shared/notifications/reminder_coordinator.dart';
import 'primary_navigation_rail.dart';
import '../settings/navigation_settings.dart';
import '../settings/settings_center.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final path = GoRouterState.of(context).uri.path;
    final module = primaryModuleForPath(path);
    final compact = useCompactLayout(context);
    final isMe = path == '/me';
    final visibility = ref.watch(navigationSettingsProvider).value;
    final visibleModules = PrimaryModule.values
        .where(
          (m) =>
              (m != PrimaryModule.dashboard || visibility.dashboardVisible) &&
              (m != PrimaryModule.tools || visibility.toolsVisible) &&
              (m != PrimaryModule.notes || visibility.knowledgeVisible) &&
              ((m != PrimaryModule.customers && m != PrimaryModule.orders) ||
                  visibility.crmVisible),
        )
        .toList();

    if (!compact && !isMe && width >= FlyBreakpoints.expanded) {
      return _withGlobalSearch(
        context,
        Scaffold(
          body: Row(
            children: [
              _PrimaryRail(
                module: module,
                onSelected: (value) => _navigateModule(context, ref, value),
              ),
              const VerticalDivider(width: 1),
              ..._expandedWorkspace(
                module,
                child,
                ref,
                width,
                isTaskWide: path == '/tasks/review' || path == '/tasks/focus',
              ),
            ],
          ),
        ),
      );
    }

    if (!compact && !isMe && width >= FlyBreakpoints.medium) {
      return _withGlobalSearch(
        context,
        Scaffold(
          body: Row(
            children: [
              _PrimaryRail(
                module: module,
                onSelected: (value) => _navigateModule(context, ref, value),
              ),
              const VerticalDivider(width: 1),
              if (module == PrimaryModule.tasks) ...[
                const SizedBox(
                  width: FlyMetrics.taskSidebarWidth,
                  child: TaskSidebar(),
                ),
                const VerticalDivider(width: 1),
              ] else if (module == PrimaryModule.customers) ...[
                const SizedBox(
                  width: FlyMetrics.taskSidebarWidth,
                  child: CustomerSidebar(),
                ),
                const VerticalDivider(width: 1),
              ] else if (module == PrimaryModule.orders) ...[
                const SizedBox(
                  width: FlyMetrics.taskSidebarWidth,
                  child: OrderSidebar(),
                ),
                const VerticalDivider(width: 1),
              ] else if (module == PrimaryModule.tools) ...[
                const SizedBox(
                  width: FlyMetrics.taskSidebarWidth,
                  child: ToolsSidebar(),
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(child: child),
            ],
          ),
        ),
      );
    }

    return _withGlobalSearch(
      context,
      Scaffold(
        appBar: isPhoneLayout(context)
            ? null
            : AppBar(
                leading: const Center(child: LocalProfileAvatar()),
                title: const Text('Fly'),
                actions: [
                  IconButton(
                    key: const ValueKey('primary-settings'),
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const SettingsCenter(),
                    ),
                  ),
                ],
              ),
        body: isPhoneLayout(context)
            ? SafeArea(
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: LocalProfileAvatar(hideWhenEmpty: true),
                        ),
                        Spacer(),
                        MobileSyncButton(),
                      ],
                    ),
                    Expanded(child: child),
                  ],
                ),
              )
            : child,
        bottomNavigationBar: _compactNavigation(
          context,
          ref,
          module,
          visibleModules,
          isMe: isMe,
        ),
      ),
    );
  }

  Widget _compactNavigation(
    BuildContext context,
    WidgetRef ref,
    PrimaryModule selected,
    List<PrimaryModule> visible, {
    bool isMe = false,
  }) {
    final main = [
      PrimaryModule.customers,
      PrimaryModule.orders,
      PrimaryModule.tasks,
      PrimaryModule.files,
    ].where(visible.contains).toList();
    final current =
        selected == PrimaryModule.calendar || selected == PrimaryModule.matrix
        ? PrimaryModule.tasks
        : selected;
    return NavigationBar(
      key: const ValueKey('compact-navigation'),
      height: 64,
      selectedIndex: !isMe && main.contains(current)
          ? main.indexOf(current)
          : main.length,
      onDestinationSelected: (index) {
        if (index < main.length) {
          _navigateModule(context, ref, main[index]);
          return;
        }
        context.go('/me');
      },
      destinations: [
        for (final m in main)
          NavigationDestination(
            icon: Icon(_moduleIcon(m)),
            label: _moduleLabel(context, m),
          ),
        NavigationDestination(
          icon: const Icon(Icons.person_outline),
          label: context.l10n.isZh ? '我的' : 'Me',
        ),
      ],
    );
  }

  IconData _moduleIcon(PrimaryModule module) => switch (module) {
    PrimaryModule.dashboard => Icons.home_outlined,
    PrimaryModule.customers => Icons.people_outline,
    PrimaryModule.orders => Icons.receipt_long_outlined,
    PrimaryModule.tasks => Icons.check_box_outlined,
    PrimaryModule.files => Icons.folder_outlined,
    PrimaryModule.notes => Icons.menu_book_outlined,
    PrimaryModule.tools => Icons.handyman_outlined,
    PrimaryModule.calendar => Icons.calendar_month_outlined,
    PrimaryModule.matrix => Icons.grid_view_outlined,
  };
  String _moduleLabel(BuildContext context, PrimaryModule module) =>
      context.l10n.t(switch (module) {
        PrimaryModule.dashboard => 'navHome',
        PrimaryModule.customers => 'navCustomers',
        PrimaryModule.orders => 'navOrders',
        PrimaryModule.tasks => 'tasks',
        PrimaryModule.files => 'navFiles',
        PrimaryModule.notes => 'navNotes',
        PrimaryModule.tools => 'tools',
        PrimaryModule.calendar => 'calendar',
        PrimaryModule.matrix => 'matrix',
      });

  Widget _withGlobalSearch(BuildContext context, Widget child) =>
      CallbackShortcuts(
        bindings: {
          if (!isPhoneLayout(context))
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                showGlobalSearchPalette(context),
        },
        child: NoteCloseGuard(
          child: Focus(
            autofocus: true,
            child: ReminderCoordinator(child: child),
          ),
        ),
      );

  List<Widget> _expandedWorkspace(
    PrimaryModule module,
    Widget child,
    WidgetRef ref,
    double width, {
    required bool isTaskWide,
  }) => switch (module) {
    PrimaryModule.dashboard => [Expanded(child: child)],
    PrimaryModule.tasks => [
      const SizedBox(width: FlyMetrics.taskSidebarWidth, child: TaskSidebar()),
      const VerticalDivider(width: 1),
      if (isTaskWide)
        Expanded(child: child)
      else ...[
        SizedBox(width: FlyMetrics.taskListWidth, child: child),
        const VerticalDivider(width: 1),
        Expanded(child: _taskDetail(ref)),
      ],
    ],
    PrimaryModule.customers => _customerWorkspace(child, ref, width),
    PrimaryModule.orders => _orderWorkspace(child, ref, width),
    PrimaryModule.tools => [
      const SizedBox(width: FlyMetrics.taskSidebarWidth, child: ToolsSidebar()),
      const VerticalDivider(width: 1),
      Expanded(child: child),
    ],
    PrimaryModule.calendar ||
    PrimaryModule.matrix ||
    PrimaryModule.files ||
    PrimaryModule.notes => [Expanded(child: child)],
  };

  List<Widget> _customerWorkspace(
    Widget child,
    WidgetRef ref,
    double windowWidth,
  ) {
    final id = ref.watch(selectedCustomerIdProvider);
    final extension = ref.watch(customerDetailExtensionProvider);
    final showExtension = id != null && extension != DetailExtensionType.none;
    final dockExtension = showExtension && windowWidth >= 1580;
    final extensionPanel = id == null
        ? null
        : CustomerExtensionPanel(
            customerId: id,
            type: extension,
            onClose: () =>
                ref.read(customerDetailExtensionProvider.notifier).state =
                    DetailExtensionType.none,
          );

    return [
      const SizedBox(
        width: FlyMetrics.taskSidebarWidth,
        child: CustomerSidebar(),
      ),
      const VerticalDivider(width: 1),
      SizedBox(width: FlyMetrics.taskListWidth, child: child),
      const VerticalDivider(width: 1),
      Expanded(
        child: dockExtension
            ? _customerDetail(ref)
            : Stack(
                children: [
                  Positioned.fill(child: _customerDetail(ref)),
                  if (showExtension)
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      width: 400,
                      child: AnimatedSwitcher(
                        duration: FlyMotion.standard,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(.06, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(extension),
                          child: extensionPanel!,
                        ),
                      ),
                    ),
                ],
              ),
      ),
      if (dockExtension) ...[
        const VerticalDivider(width: 1),
        SizedBox(width: 400, child: extensionPanel),
      ],
    ];
  }

  List<Widget> _orderWorkspace(
    Widget child,
    WidgetRef ref,
    double windowWidth,
  ) {
    final id = ref.watch(selectedOrderIdProvider);
    final extension = ref.watch(orderExtensionProvider);
    final showExtension = id != null && extension != OrderExtensionType.none;
    final dockExtension = showExtension && windowWidth >= 1620;
    final extensionPanel = id == null
        ? null
        : OrderExtensionPanel(
            orderId: id,
            type: extension,
            onClose: () => ref.read(orderExtensionProvider.notifier).state =
                OrderExtensionType.none,
          );

    return [
      const SizedBox(width: FlyMetrics.taskSidebarWidth, child: OrderSidebar()),
      const VerticalDivider(width: 1),
      SizedBox(width: FlyMetrics.taskListWidth, child: child),
      const VerticalDivider(width: 1),
      Expanded(
        child: dockExtension
            ? _orderDetail(ref)
            : Stack(
                children: [
                  Positioned.fill(child: _orderDetail(ref)),
                  if (showExtension)
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      width: 420,
                      child: AnimatedSwitcher(
                        duration: FlyMotion.standard,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(.06, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(extension),
                          child: extensionPanel!,
                        ),
                      ),
                    ),
                ],
              ),
      ),
      if (dockExtension) ...[
        const VerticalDivider(width: 1),
        SizedBox(width: 420, child: extensionPanel),
      ],
    ];
  }

  Widget _taskDetail(WidgetRef ref) {
    final id = ref.watch(selectedTaskIdProvider);
    return id == null
        ? const _DetailPlaceholder()
        : TaskDetailPanel(taskId: id);
  }

  Widget _customerDetail(WidgetRef ref) {
    final id = ref.watch(selectedCustomerIdProvider);
    return id == null
        ? const _DetailPlaceholder(
            title: 'selectCustomer',
            hint: 'selectCustomerHint',
          )
        : CustomerDetailPanel(customerId: id);
  }

  Widget _orderDetail(WidgetRef ref) {
    final id = ref.watch(selectedOrderIdProvider);
    return id == null
        ? const _DetailPlaceholder(
            title: 'selectOrder',
            hint: 'selectOrderHint',
          )
        : OrderDetailPanel(orderId: id);
  }

  static void _navigateModule(
    BuildContext context,
    WidgetRef ref,
    PrimaryModule module,
  ) {
    ref.read(selectedTaskIdProvider.notifier).state = null;
    if (module != PrimaryModule.customers) {
      ref.read(selectedCustomerIdProvider.notifier).state = null;
      ref.read(customerDetailExtensionProvider.notifier).state =
          DetailExtensionType.none;
    }
    if (module != PrimaryModule.orders) {
      ref.read(selectedOrderIdProvider.notifier).state = null;
      ref.read(orderExtensionProvider.notifier).state = OrderExtensionType.none;
    }
    context.go(switch (module) {
      PrimaryModule.customers =>
        useCompactLayout(context) ? '/customers/all' : '/customers/today',
      PrimaryModule.dashboard => '/dashboard',
      PrimaryModule.orders => '/orders/all',
      PrimaryModule.tasks => '/tasks/today',
      PrimaryModule.calendar => '/calendar',
      PrimaryModule.matrix => '/matrix',
      PrimaryModule.files => '/files',
      PrimaryModule.notes => enableKnowledgeHub ? '/knowledge' : '/notes',
      PrimaryModule.tools => '/tools/container-loading',
    });
  }
}

class _PrimaryRail extends StatelessWidget {
  const _PrimaryRail({required this.module, required this.onSelected});
  final PrimaryModule module;
  final ValueChanged<PrimaryModule> onSelected;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: FlyMetrics.primaryRailWidth,
    child: PrimaryNavigationRail(
      selectedModule: module,
      onSelected: onSelected,
    ),
  );
}

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder({this.title, this.hint});
  final String? title;
  final String? hint;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back_rounded, size: 26),
            const SizedBox(height: FlySpacing.sm),
            Text(
              context.l10n.t(title ?? 'noTask'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: FlySpacing.xs),
            Text(
              context.l10n.t(hint ?? 'noTaskHint'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
