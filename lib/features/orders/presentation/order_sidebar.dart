import 'package:flutter/material.dart';

import '../../../l10n/crm_copy.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../domain/order_lifecycle.dart';
import '../../../l10n/fly_localizations.dart';
import 'order_providers.dart';

class OrderSidebar extends ConsumerWidget {
  const OrderSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
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
              const Spacer(),
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
}

class _OrderSideItem extends StatelessWidget {
  const _OrderSideItem({
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
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
    ),
  );
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
