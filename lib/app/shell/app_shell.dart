import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/tasks/presentation/task_detail_panel.dart';
import '../../features/tasks/presentation/task_providers.dart';
import '../../shared/design_system/design_tokens.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  static const _destinations = [
    _Destination('/today', 'Today', Icons.today_outlined, Icons.today),
    _Destination('/inbox', 'Inbox', Icons.inbox_outlined, Icons.inbox),
    _Destination(
      '/upcoming',
      'Upcoming',
      Icons.event_note_outlined,
      Icons.event_note,
    ),
    _Destination(
      '/calendar',
      'Calendar',
      Icons.calendar_month_outlined,
      Icons.calendar_month,
    ),
    _Destination(
      '/matrix',
      'Matrix',
      Icons.grid_view_outlined,
      Icons.grid_view,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final path = GoRouterState.of(context).uri.path;
    final selectedTaskId = ref.watch(selectedTaskIdProvider);

    if (width >= FlyBreakpoints.expanded) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: FlyMetrics.sidebarWidth,
              child: _Sidebar(path: path),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
            if (selectedTaskId != null) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: FlyMetrics.detailWidth,
                child: TaskDetailPanel(taskId: selectedTaskId),
              ),
            ],
          ],
        ),
      );
    }

    if (width >= FlyBreakpoints.medium) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex(path),
              onDestinationSelected: (index) =>
                  context.go(_destinations[index].path),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.only(bottom: FlySpacing.md),
                child: _FlyMark(),
              ),
              destinations: [
                for (final item in _destinations)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    final compactIndex = _selectedIndex(path);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        height: 64,
        selectedIndex: compactIndex,
        onDestinationSelected: (index) => context.go(_destinations[index].path),
        destinations: [
          for (final item in _destinations)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }

  int _selectedIndex(String path) {
    final index = _destinations.indexWhere(
      (item) => path.startsWith(item.path),
    );
    return index < 0 ? 0 : index;
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(taskListsProvider).valueOrNull ?? const [];
    final themeMode = ref.watch(themeModeProvider);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FlySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  _FlyMark(),
                  SizedBox(width: FlySpacing.sm),
                  Text(
                    'Fly',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: FlySpacing.xl),
              for (final item in AppShell._destinations)
                _SideItem(item: item, selected: path.startsWith(item.path)),
              const SizedBox(height: FlySpacing.lg),
              Text('LISTS', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: FlySpacing.xs),
              for (final list in lists)
                _SideItem(
                  item: _Destination(
                    '/list/${list.id}',
                    list.name,
                    Icons.circle_outlined,
                    Icons.circle,
                  ),
                  selected: path == '/list/${list.id}',
                ),
              const Spacer(),
              PopupMenuButton<ThemeMode>(
                initialValue: themeMode,
                onSelected: (value) =>
                    ref.read(themeModeProvider.notifier).state = value,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: ThemeMode.system,
                    child: Text('Follow system'),
                  ),
                  PopupMenuItem(value: ThemeMode.light, child: Text('Light')),
                  PopupMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: FlySpacing.sm,
                  ),
                  leading: Icon(
                    themeMode == ThemeMode.dark
                        ? Icons.dark_mode_outlined
                        : Icons.contrast,
                  ),
                  title: const Text('Appearance'),
                  trailing: const Icon(Icons.unfold_more, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({required this.item, required this.selected});

  final _Destination item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FlySpacing.xxs),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlyRadius.md),
        ),
        leading: Icon(selected ? item.selectedIcon : item.icon, size: 20),
        title: Text(item.label),
        onTap: () => context.go(item.path),
      ),
    );
  }
}

class _FlyMark extends StatelessWidget {
  const _FlyMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: FlyColors.accent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Stack(
          children: [
            Positioned(left: 7, top: 8, child: _Wing(width: 16)),
            Positioned(left: 11, top: 15, child: _Wing(width: 12)),
          ],
        ),
      ),
    );
  }
}

class _Wing extends StatelessWidget {
  const _Wing({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.28,
    child: Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _Destination {
  const _Destination(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
