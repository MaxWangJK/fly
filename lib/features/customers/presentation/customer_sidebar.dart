import '../domain/customer_lifecycle.dart';
import '../../../l10n/fly_localizations.dart';

import 'package:flutter/material.dart';

import '../../../l10n/crm_copy.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../domain/customer.dart';
import 'customer_providers.dart';

class CustomerSidebar extends ConsumerWidget {
  const CustomerSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final categories =
        ref.watch(customerCategoriesProvider).valueOrNull ?? const [];
    return Material(
      key: const ValueKey('customer-secondary-sidebar'),
      color: context.flyColors.secondarySidebar,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 2, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.crmCopy('客户'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('customer-config-button'),
                      tooltip: context.crmCopy('配置客户状态与来源'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const _CrmConfigDialog(),
                      ),
                      icon: const Icon(Icons.tune, size: 17),
                    ),
                  ],
                ),
              ),
              _SideItem(
                label: context.crmCopy('今天'),
                icon: Icons.today_outlined,
                selected: path == '/customers/today',
                onTap: () => _go(context, ref, '/customers/today'),
              ),
              _SideItem(
                label: context.crmCopy('最近7天'),
                icon: Icons.date_range_outlined,
                selected: path == '/customers/next7days',
                onTap: () => _go(context, ref, '/customers/next7days'),
              ),
              _SideItem(
                label: context.crmCopy('全部客户'),
                icon: Icons.people_outline,
                selected: path == '/customers/all',
                onTap: () => _go(context, ref, '/customers/all'),
              ),
              _SideItem(
                label: context.crmCopy('收集箱'),
                icon: Icons.inbox_outlined,
                selected: path == '/customers/inbox',
                onTap: () => _go(context, ref, '/customers/inbox'),
              ),
              const SizedBox(height: FlySpacing.lg),
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 4, bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.crmCopy('客户级别'),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('add-customer-category'),
                      tooltip: context.crmCopy('新增客户级别'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _editCategory(context, ref),
                      icon: const Icon(Icons.add, size: 18),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final categoryPath = '/customers/category/${category.id}';
                    return _CategoryItem(
                      category: category,
                      selected: path == categoryPath,
                      onTap: () => _go(
                        context,
                        ref,
                        categoryPath,
                        categoryTagId: category.tagId,
                      ),
                      onRename: () =>
                          _editCategory(context, ref, category: category),
                      onMoveUp: index == 0
                          ? null
                          : () => _moveCategory(ref, categories, index, -1),
                      onMoveDown: index == categories.length - 1
                          ? null
                          : () => _moveCategory(ref, categories, index, 1),
                      onDeactivate: () => ref
                          .read(customerRepositoryProvider)
                          .setCategoryActive(category.id, active: false),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: FlySpacing.xs),
              _SideItem(
                label: context.crmCopy('已删除'),
                icon: Icons.delete_outline,
                selected: path == '/customers/deleted',
                onTap: () => _go(context, ref, '/customers/deleted'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _go(
    BuildContext context,
    WidgetRef ref,
    String path, {
    String? categoryTagId,
  }) {
    ref.read(selectedCustomerIdProvider.notifier).state = null;
    ref.read(customerTagFilterProvider.notifier).state = categoryTagId == null
        ? <String>{}
        : <String>{categoryTagId};
    context.go(path);
  }

  static Future<void> _editCategory(
    BuildContext context,
    WidgetRef ref, {
    CustomerCategory? category,
  }) async {
    final controller = TextEditingController(text: category?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          category == null
              ? context.crmCopy('新增客户级别')
              : context.crmCopy('重命名客户级别'),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: context.crmCopy('例如：重点客户')),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.crmCopy('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(context.crmCopy('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    if (category == null) {
      await ref.read(customerRepositoryProvider).createCategory(name.trim());
    } else {
      await ref
          .read(customerRepositoryProvider)
          .renameCategory(category.id, name.trim());
    }
  }

  static Future<void> _moveCategory(
    WidgetRef ref,
    List<CustomerCategory> categories,
    int index,
    int delta,
  ) async {
    final reordered = [...categories];
    final item = reordered.removeAt(index);
    reordered.insert(index + delta, item);
    await ref
        .read(customerRepositoryProvider)
        .reorderCategories(reordered.map((item) => item.id).toList());
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ListTile(
        dense: true,
        minTileHeight: 38,
        selected: selected,
        selectedTileColor: context.flyColors.selected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlyRadius.sm),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(icon, size: 19),
        title: Text(label),
        onTap: onTap,
      ),
    ),
  );
}

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({
    required this.category,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDeactivate,
  });
  final CustomerCategory category;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ListTile(
        dense: true,
        minTileHeight: 38,
        selected: selected,
        selectedTileColor: context.flyColors.selected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlyRadius.sm),
        ),
        contentPadding: const EdgeInsets.only(left: 12, right: 2),
        leading: Icon(Icons.circle, size: 9, color: Color(category.colorValue)),
        title: Text(
          category.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          tooltip: context.crmCopy('管理'),
          icon: const Icon(Icons.more_horiz, size: 17),
          onSelected: (value) {
            if (value == 'rename') onRename();
            if (value == 'up') onMoveUp?.call();
            if (value == 'down') onMoveDown?.call();
            if (value == 'deactivate') onDeactivate();
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'rename', child: Text(context.crmCopy('重命名'))),
            PopupMenuItem(
              value: 'up',
              enabled: onMoveUp != null,
              child: Text(context.crmCopy('上移')),
            ),
            PopupMenuItem(
              value: 'down',
              enabled: onMoveDown != null,
              child: Text(context.crmCopy('下移')),
            ),
            PopupMenuItem(
              value: 'deactivate',
              child: Text(context.crmCopy('停用')),
            ),
          ],
        ),
        onTap: onTap,
      ),
    ),
  );
}

class _CrmConfigDialog extends ConsumerWidget {
  const _CrmConfigDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statuses =
        ref.watch(customerStatusesProvider).valueOrNull ??
        const <CustomerStatus>[];
    final sources =
        ref.watch(allCustomerSourcesProvider).valueOrNull ?? const [];
    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        title: Text(context.crmCopy('客户配置')),
        content: SizedBox(
          width: 430,
          height: 440,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: context.crmCopy('客户状态')),
                  Tab(text: context.crmCopy('客户来源')),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      children: [
                        for (final stage in statuses)
                          ListTile(
                            leading: Icon(
                              Icons.circle,
                              size: 12,
                              color: Color(stage.colorValue),
                            ),
                            title: Text(
                              CustomerLifecycle.label(
                                stage.id,
                                zh: context.l10n.isZh,
                                customName: stage.name,
                              ),
                            ),
                          ),
                      ],
                    ),
                    _ConfigList(
                      names: sources.map((item) => item.name).toList(),
                      colors: sources.map((item) => item.colorValue).toList(),
                      active: sources.map((item) => item.isActive).toList(),
                      onAdd: () async {
                        final name = await _askName(
                          context,
                          context.crmCopy('新增客户来源'),
                        );
                        if (name != null) {
                          await ref
                              .read(customerRepositoryProvider)
                              .createSource(
                                name,
                                colorValue:
                                    _configColors[sources.length %
                                        _configColors.length],
                              );
                        }
                      },
                      onRename: (index) async {
                        final name = await _askName(
                          context,
                          context.crmCopy('重命名客户来源'),
                          sources[index].name,
                        );
                        if (name != null) {
                          await ref
                              .read(customerRepositoryProvider)
                              .renameSource(sources[index].id, name);
                        }
                      },
                      onToggle: (index) => ref
                          .read(customerRepositoryProvider)
                          .setSourceActive(
                            sources[index].id,
                            active: !sources[index].isActive,
                          ),
                      onColor: (index, color) => ref
                          .read(customerRepositoryProvider)
                          .setSourceColor(sources[index].id, color),
                      onMove: (index, delta) {
                        final reordered = [...sources];
                        final item = reordered.removeAt(index);
                        reordered.insert(index + delta, item);
                        return ref
                            .read(customerRepositoryProvider)
                            .reorderSources(
                              reordered.map((item) => item.id).toList(),
                            );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.crmCopy('完成')),
          ),
        ],
      ),
    );
  }
}

class _ConfigList extends StatelessWidget {
  const _ConfigList({
    required this.names,
    required this.colors,
    required this.active,
    required this.onAdd,
    required this.onRename,
    required this.onToggle,
    required this.onColor,
    required this.onMove,
  });
  final List<String> names;
  final List<int> colors;
  final List<bool> active;
  final VoidCallback onAdd;
  final ValueChanged<int> onRename;
  final ValueChanged<int> onToggle;
  final void Function(int index, int color) onColor;
  final Future<void> Function(int index, int delta) onMove;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 16),
          label: Text(context.crmCopy('新增')),
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: names.length,
          itemBuilder: (context, index) => ListTile(
            dense: true,
            enabled: active[index],
            leading: PopupMenuButton<int>(
              tooltip: context.crmCopy('颜色'),
              onSelected: (color) => onColor(index, color),
              itemBuilder: (context) => [
                for (final color in _configColors)
                  PopupMenuItem(
                    value: color,
                    child: Icon(Icons.circle, color: Color(color), size: 18),
                  ),
              ],
              child: Icon(Icons.circle, color: Color(colors[index]), size: 14),
            ),
            title: Text(names[index]),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'rename') onRename(index);
                if (value == 'toggle') onToggle(index);
                if (value == 'up' && index > 0) onMove(index, -1);
                if (value == 'down' && index < names.length - 1) {
                  onMove(index, 1);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(context.crmCopy('重命名')),
                ),
                PopupMenuItem(
                  value: 'up',
                  enabled: index > 0,
                  child: Text(context.crmCopy('上移')),
                ),
                PopupMenuItem(
                  value: 'down',
                  enabled: index < names.length - 1,
                  child: Text(context.crmCopy('下移')),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(
                    active[index]
                        ? context.crmCopy('停用')
                        : context.crmCopy('启用'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

Future<String?> _askName(
  BuildContext context,
  String title, [
  String initial = '',
]) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.crmCopy(title)),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(context.crmCopy('取消')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: Text(context.crmCopy('保存')),
        ),
      ],
    ),
  );
  controller.dispose();
  final value = result?.trim();
  return value == null || value.isEmpty ? null : value;
}

const _configColors = <int>[
  0xFF6F86B3,
  0xFF6E9B86,
  0xFFC28A58,
  0xFF9A7BAF,
  0xFFB66F78,
  0xFF5F9296,
];
