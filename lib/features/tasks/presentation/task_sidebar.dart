import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../domain/task_list.dart';
import 'task_providers.dart';

class TaskSidebar extends ConsumerWidget {
  const TaskSidebar({super.key});

  static const _primaryItems = [
    _TaskDestination(
      '/tasks/today',
      'today',
      Icons.today_outlined,
      Icons.today,
    ),
    _TaskDestination(
      '/tasks/next7days',
      'next7',
      Icons.date_range_outlined,
      Icons.date_range,
    ),
    _TaskDestination(
      '/tasks/inbox',
      'inbox',
      Icons.inbox_outlined,
      Icons.inbox,
    ),
  ];

  static const _utilityItems = [
    _TaskDestination(
      '/tasks/completed',
      'completed',
      Icons.check_circle_outline,
      Icons.check_circle,
    ),
    _TaskDestination(
      '/tasks/trash',
      'trash',
      Icons.delete_outline,
      Icons.delete,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final lists = ref.watch(taskListsProvider).valueOrNull ?? const [];
    final customLists = lists.where((list) => list.id != 'inbox').toList();
    return Material(
      key: const ValueKey('task-secondary-sidebar'),
      color: context.flyColors.secondarySidebar,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            FlySpacing.sm,
            FlySpacing.md,
            FlySpacing.sm,
            FlySpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FlySpacing.sm,
                  FlySpacing.xxs,
                  FlySpacing.sm,
                  FlySpacing.md,
                ),
                child: Text(
                  context.l10n.t('tasks'),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (final item in _primaryItems)
                _SidebarItem(
                  label: context.l10n.t(item.labelKey),
                  icon: path == item.path ? item.selectedIcon : item.icon,
                  selected: path == item.path,
                  onTap: () => _navigate(context, ref, item.path),
                ),
              const SizedBox(height: FlySpacing.lg),
              const Divider(height: 1),
              _SidebarItem(
                label: context.l10n.t('dailyReview'),
                icon: Icons.fact_check_outlined,
                selected: path == '/tasks/review',
                onTap: () => _navigate(context, ref, '/tasks/review'),
              ),
              _SidebarItem(
                label: context.l10n.isZh ? '我的聚焦' : 'My Focus',
                icon: Icons.center_focus_strong_outlined,
                selected: path == '/tasks/focus',
                onTap: () => _navigate(context, ref, '/tasks/focus'),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.only(
                  left: FlySpacing.sm,
                  right: FlySpacing.xxs,
                  bottom: FlySpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.t('lists'),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.t('newList'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _showListDialog(context, ref),
                      icon: const Icon(Icons.add, size: 18),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Scrollbar(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: customLists.length,
                    itemBuilder: (context, index) {
                      final list = customLists[index];
                      final listPath = '/tasks/list/${list.id}';
                      return _ListSidebarItem(
                        list: list,
                        selected: path == listPath,
                        onTap: () => _navigate(context, ref, listPath),
                        onRename: () =>
                            _showListDialog(context, ref, list: list),
                        onDelete: () => _confirmDelete(context, ref, list),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: FlySpacing.xs),
              const Divider(height: 1),
              const SizedBox(height: FlySpacing.xs),
              for (final item in _utilityItems)
                _SidebarItem(
                  label: context.l10n.t(item.labelKey),
                  icon: path == item.path ? item.selectedIcon : item.icon,
                  selected: path == item.path,
                  onTap: () => _navigate(context, ref, item.path),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static void _navigate(BuildContext context, WidgetRef ref, String path) {
    ref.read(selectedTaskIdProvider.notifier).state = null;
    context.go(path);
  }

  Future<void> _showListDialog(
    BuildContext context,
    WidgetRef ref, {
    FlyTaskList? list,
  }) async {
    final controller = TextEditingController(text: list?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t(list == null ? 'newList' : 'rename')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: context.l10n.t('listName')),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(context.l10n.t(list == null ? 'create' : 'confirm')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    if (list == null) {
      final created = await ref.read(taskRepositoryProvider).createList(name);
      if (context.mounted) context.go('/tasks/list/${created.id}');
    } else {
      await ref.read(taskRepositoryProvider).renameList(list.id, name);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    FlyTaskList list,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('deleteList')),
        content: Text(context.l10n.deleteListMessage(list.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(taskRepositoryProvider).deleteList(list.id);
    if (context.mounted &&
        GoRouterState.of(context).uri.path == '/tasks/list/${list.id}') {
      context.go('/tasks/inbox');
    }
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FlySpacing.xxs),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ListTile(
          dense: true,
          minTileHeight: 38,
          contentPadding: const EdgeInsets.symmetric(horizontal: FlySpacing.sm),
          selected: selected,
          selectedTileColor: context.flyColors.selected,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FlyRadius.sm),
          ),
          leading: Icon(icon, size: FlyMetrics.iconMd),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _ListSidebarItem extends StatelessWidget {
  const _ListSidebarItem({
    required this.list,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final FlyTaskList list;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FlySpacing.xxs),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ListTile(
          dense: true,
          minTileHeight: 38,
          contentPadding: const EdgeInsets.only(
            left: FlySpacing.sm,
            right: FlySpacing.xxs,
          ),
          selected: selected,
          selectedTileColor: context.flyColors.selected,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FlyRadius.sm),
          ),
          leading: Icon(Icons.circle, size: 9, color: Color(list.colorValue)),
          title: Text(list.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: SizedBox.square(
            dimension: 30,
            child: PopupMenuButton<String>(
              tooltip: context.l10n.t('more'),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_horiz, size: 17),
              onSelected: (value) =>
                  value == 'rename' ? onRename() : onDelete(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(context.l10n.t('rename')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.l10n.t('delete')),
                ),
              ],
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _TaskDestination {
  const _TaskDestination(
    this.path,
    this.labelKey,
    this.icon,
    this.selectedIcon,
  );

  final String path;
  final String labelKey;
  final IconData icon;
  final IconData selectedIcon;
}
