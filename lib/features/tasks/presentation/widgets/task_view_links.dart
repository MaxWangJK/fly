import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/design_system/responsive_layout.dart';
import '../../../../l10n/fly_localizations.dart';
import '../../domain/task_list.dart';
import '../../domain/task_list_path.dart';
import '../task_providers.dart';

class TaskViewLinks extends ConsumerWidget {
  const TaskViewLinks({required this.current, super.key});
  final String current;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = isPhoneLayout(context);
    final active =
        phone &&
            current == 'tasks' &&
            GoRouterState.of(context).uri.path != '/tasks/today'
        ? 'lists'
        : current;
    final links = [
      (
        'tasks',
        phone ? (context.l10n.isZh ? '今天' : 'Today') : context.l10n.t('tasks'),
        '/tasks/today',
      ),
      if (phone) ('review', '复盘', '/tasks/review'),
      if (phone) ('lists', '清单', ''),
      ('calendar', context.l10n.t('calendar'), '/calendar'),
      ('matrix', context.l10n.t('matrix'), '/matrix'),
    ];
    final route = phone
        ? GoRouterState.of(context).uri.pathSegments
        : <String>[];
    final path = route.length == 3 && route[0] == 'tasks' && route[1] == 'list'
        ? taskListPath(ref.watch(taskListsProvider).valueOrNull ?? [], route[2])
        : <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final link in links)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton(
                    key: ValueKey('task-view-${link.$1}'),
                    style: TextButton.styleFrom(
                      backgroundColor: active == link.$1
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      minimumSize: const Size(48, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: () => link.$1 == 'lists'
                        ? showModalBottomSheet<void>(
                            context: context,
                            useRootNavigator: true,
                            isScrollControlled: true,
                            useSafeArea: true,
                            showDragHandle: true,
                            builder: (_) => const _ListPicker(),
                          )
                        : context.go(link.$3),
                    child: Text(link.$2),
                  ),
                ),
            ],
          ),
        ),
        if (path.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
            child: Tooltip(
              message: path.join(' / '),
              child: Text(
                path.length <= 3
                    ? path.join(' / ')
                    : '… / ${path.sublist(path.length - 3).join(' / ')}',
                key: const ValueKey('task-list-path'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
      ],
    );
  }
}

class _ListPicker extends ConsumerWidget {
  const _ListPicker();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(taskListsProvider).valueOrNull ?? <FlyTaskList>[];
    final custom = lists.where((l) => l.id != 'inbox').toList();
    void open(String path) {
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.go(path);
    }

    Future<void> create([String? parent]) async {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(parent == null ? '新建清单' : '新建子清单'),
          content: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(dialog, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, controller.text),
              child: const Text('创建'),
            ),
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      controller.dispose();
      if (name == null || name.trim().isEmpty || !context.mounted) return;
      try {
        final list = await ref
            .read(taskRepositoryProvider)
            .createList(name, parentId: parent);
        if (context.mounted) open('/tasks/list/${list.id}');
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }

    Widget branch(FlyTaskList list, Set<String> ancestors) {
      final seen = {...ancestors, list.id};
      final children = custom
          .where((l) => l.parentId == list.id && !seen.contains(l.id))
          .toList();
      final row = ListTile(
        title: Text(list.name),
        onTap: () => open('/tasks/list/${list.id}'),
        leading: Icon(Icons.list, color: Color(list.colorValue)),
        trailing: IconButton(
          tooltip: '新建子清单',
          icon: const Icon(Icons.add),
          onPressed: () => create(list.id),
        ),
      );
      if (children.isEmpty) return row;
      return ExpansionTile(
        key: PageStorageKey(list.id),
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(child: Text(list.name)),
            IconButton(
              tooltip: '新建子清单',
              onPressed: () => create(list.id),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        leading: IconButton(
          tooltip: '打开清单',
          icon: const Icon(Icons.list),
          onPressed: () => open('/tasks/list/${list.id}'),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              children: children.map((l) => branch(l, seen)).toList(),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: ListView(
        key: const ValueKey('mobile-list-picker'),
        children: [
          const ListTile(title: Text('清单与筛选')),
          for (final item in [
            ('全部任务', '/tasks/all'),
            ('收集箱', '/tasks/inbox'),
            ('未来7天', '/tasks/next7days'),
            ('已完成', '/tasks/completed'),
            ('最近删除', '/tasks/trash'),
          ])
            ListTile(title: Text(item.$1), onTap: () => open(item.$2)),
          const Divider(),
          ListTile(
            title: const Text('我的清单'),
            trailing: IconButton(
              tooltip: '新建清单',
              onPressed: create,
              icon: const Icon(Icons.add),
            ),
          ),
          for (final list in custom.where(
            (l) => l.parentId == null || !custom.any((p) => p.id == l.parentId),
          ))
            branch(list, {}),
        ],
      ),
    );
  }
}
