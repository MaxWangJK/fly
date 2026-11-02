import 'package:flutter/material.dart';

import '../../../l10n/crm_copy.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../domain/order.dart';
import '../domain/order_lifecycle.dart';
import '../../../l10n/fly_localizations.dart';
import 'order_providers.dart';

class OrderSidebar extends ConsumerWidget {
  const OrderSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final visibleTags =
        ref.watch(popularOrderTagsProvider).valueOrNull ?? const [];
    return Material(
      key: const ValueKey('order-secondary-sidebar'),
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
                        context.crmCopy('订单'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('order-status-config-button'),
                      tooltip: context.crmCopy('配置订单状态'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const _OrderStatusDialog(),
                      ),
                      icon: const Icon(Icons.tune, size: 17),
                    ),
                  ],
                ),
              ),
              _OrderSideItem(
                label: context.crmCopy('全部订单'),
                icon: Icons.receipt_long_outlined,
                selected: path == '/orders/all',
                onTap: () => _go(context, ref, '/orders/all'),
              ),
              _OrderSideItem(
                label: context.crmCopy('重要订单'),
                icon: Icons.flag_outlined,
                selected: path == '/orders/important',
                onTap: () => _go(context, ref, '/orders/important'),
              ),
              _OrderSideItem(
                label: context.crmCopy('一般订单'),
                icon: Icons.outlined_flag,
                selected: path == '/orders/normal',
                onTap: () => _go(context, ref, '/orders/normal'),
              ),
              const SizedBox(height: FlySpacing.lg),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.crmCopy('订单标签'),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('manage-order-tags'),
                      tooltip: context.crmCopy('管理标签'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const _OrderTagManagerDialog(),
                      ),
                      icon: const Icon(Icons.more_horiz, size: 18),
                    ),
                    IconButton(
                      tooltip: context.crmCopy('新建标签'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _createTag(context, ref),
                      icon: const Icon(Icons.add, size: 18),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final tag in visibleTags)
                      _OrderSideItem(
                        label: tag.name,
                        icon: Icons.circle,
                        iconColor: Color(tag.colorValue),
                        selected: path == '/orders/tag/${tag.id}',
                        onTap: () => _go(context, ref, '/orders/tag/${tag.id}'),
                        trailing: PopupMenuButton<String>(
                          tooltip: context.crmCopy('管理标签'),
                          icon: const Icon(Icons.more_horiz, size: 16),
                          onSelected: (value) async {
                            if (value == 'rename') {
                              await _renameTag(context, ref, tag);
                            } else if (value == 'disable') {
                              await ref
                                  .read(orderRepositoryProvider)
                                  .setTagActive(tag.id, active: false);
                              if (path == '/orders/tag/${tag.id}' &&
                                  context.mounted) {
                                _go(context, ref, '/orders/all');
                              }
                            } else if (value == 'delete') {
                              await _deleteTag(context, ref, tag);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text(context.crmCopy('重命名')),
                            ),
                            PopupMenuItem(
                              value: 'disable',
                              child: Text(context.crmCopy('停用')),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(context.crmCopy('删除')),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: FlySpacing.xs),
              _OrderSideItem(
                label: context.crmCopy('已删除'),
                icon: Icons.delete_outline,
                selected: path == '/orders/deleted',
                onTap: () => _go(context, ref, '/orders/deleted'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _go(BuildContext context, WidgetRef ref, String path) {
    ref.read(selectedOrderIdProvider.notifier).state = null;
    context.go(path);
  }

  static Future<void> _createTag(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.crmCopy('新建订单标签')),
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
            child: Text(context.crmCopy('创建')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(orderRepositoryProvider).findOrCreateTag(name.trim());
    }
  }

  static Future<void> _renameTag(
    BuildContext context,
    WidgetRef ref,
    OrderTag tag,
  ) async {
    final name = await _orderStatusName(
      context,
      context.crmCopy('重命名订单标签'),
      tag.name,
    );
    if (name != null) {
      await ref.read(orderRepositoryProvider).renameTag(tag.id, name);
    }
  }

  static Future<void> _deleteTag(
    BuildContext context,
    WidgetRef ref,
    OrderTag tag,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除标签“${tag.name}”？'),
        content: Text(context.crmCopy('标签会从客户、订单和任务中移除；客户级别关联标签不能在这里删除。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.crmCopy('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: FlyColors.danger),
            child: Text(context.crmCopy('删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(orderRepositoryProvider).deleteTag(tag.id);
    } on StateError {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.crmCopy('客户级别关联标签请在“客户级别”中管理'))),
        );
      }
    }
  }
}

class _OrderSideItem extends StatelessWidget {
  const _OrderSideItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.iconColor,
    this.trailing,
  });
  final String label;
  final IconData icon;
  final Color? iconColor;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

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
        contentPadding: EdgeInsets.only(
          left: 12,
          right: trailing == null ? 12 : 2,
        ),
        leading: Icon(
          icon,
          size: icon == Icons.circle ? 9 : 19,
          color: iconColor,
        ),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: trailing,
        onTap: onTap,
      ),
    ),
  );
}

class _OrderTagManagerDialog extends ConsumerWidget {
  const _OrderTagManagerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags =
        ref.watch(allOrderTagsIncludingInactiveProvider).valueOrNull ??
        const [];
    return AlertDialog(
      title: Text(context.crmCopy('订单标签')),
      content: SizedBox(
        width: 410,
        height: 430,
        child: ListView.builder(
          itemCount: tags.length,
          itemBuilder: (context, index) {
            final tag = tags[index];
            return ListTile(
              dense: true,
              enabled: tag.isActive,
              leading: Icon(
                Icons.circle,
                size: 10,
                color: Color(tag.colorValue),
              ),
              title: Text(tag.name),
              subtitle: tag.isActive ? null : Text(context.crmCopy('已停用')),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'rename') {
                    await OrderSidebar._renameTag(context, ref, tag);
                  } else if (value == 'toggle') {
                    await ref
                        .read(orderRepositoryProvider)
                        .setTagActive(tag.id, active: !tag.isActive);
                  } else if (value == 'delete') {
                    await OrderSidebar._deleteTag(context, ref, tag);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(context.crmCopy('重命名')),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      tag.isActive
                          ? context.crmCopy('停用')
                          : context.crmCopy('重新启用'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(context.crmCopy('删除')),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.crmCopy('完成')),
        ),
      ],
    );
  }
}

class _OrderStatusDialog extends ConsumerWidget {
  const _OrderStatusDialog();
  @override
  Widget build(BuildContext context, WidgetRef ref) => AlertDialog(
    title: Text(context.crmCopy('订单状态')),
    content: SizedBox(
      width: 410,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final stage in OrderLifecycle.stages)
            ListTile(
              dense: true,
              leading: Icon(Icons.circle, size: 12, color: Color(stage.$4)),
              title: Text(context.l10n.isZh ? stage.$2 : stage.$3),
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
  );
}

Future<String?> _orderStatusName(
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
