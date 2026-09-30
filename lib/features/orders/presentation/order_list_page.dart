import '../../../l10n/service_error_copy.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/crm_copy.dart';
import '../../../l10n/fly_localizations.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/workspace_empty_state.dart';
import '../../../shared/design_system/destructive_action.dart';
import '../../../shared/export/fly_excel_export_action.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/customer_providers.dart';
import '../domain/order.dart';
import 'order_providers.dart';

class OrderListPage extends ConsumerStatefulWidget {
  const OrderListPage({required this.projection, this.tagId, super.key});
  final OrderProjection projection;
  final String? tagId;

  @override
  ConsumerState<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends ConsumerState<OrderListPage> {
  static const _captureContextMenu = bool.fromEnvironment(
    'FLY_CAPTURE_ORDER_CONTEXT_MENU',
  );
  final _searchController = TextEditingController();

  void _selectFirstVisible(List<SalesOrder> items) {
    if (items.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selected = ref.read(selectedOrderIdProvider);
      if (items.any((item) => item.id == selected)) return;
      ref.read(selectedOrderIdProvider.notifier).state = items.first.id;
      ref.read(orderExtensionProvider.notifier).state = OrderExtensionType.none;
    });
  }

  @override
  void initState() {
    super.initState();
    if (_captureContextMenu) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        await showFlyDeleteContextMenu(
          context,
          const Offset(550, 235),
          label: context.crmCopy('删除订单'),
        );
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showOrderDeleteMenu(SalesOrder order, Offset position) async {
    final selected = await showFlyDeleteContextMenu(
      context,
      position,
      label: context.crmCopy('删除订单'),
    );
    if (!selected || !mounted) return;
    final confirmed = await confirmFlyDestructiveAction(
      context,
      title: context.l10n.isZh
          ? '确定删除订单 ${order.orderNumber}？'
          : 'Delete order ${order.orderNumber}?',
      message: context.crmCopy('订单将进入“已删除”。'),
      confirmLabel: context.crmCopy('删除订单'),
    );
    if (!confirmed) return;
    await ref.read(orderRepositoryProvider).softDeleteOrder(order.id);
    if (ref.read(selectedOrderIdProvider) == order.id) {
      ref.read(selectedOrderIdProvider.notifier).state = null;
      ref.read(orderExtensionProvider.notifier).state = OrderExtensionType.none;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.crmCopy('已移动到已删除'))));
  }

  @override
  Widget build(BuildContext context) {
    final route = (projection: widget.projection, tagId: widget.tagId);
    final orders = ref.watch(orderListProvider(route));
    final visibleItems = orders.valueOrNull;
    if (visibleItems != null) _selectFirstVisible(visibleItems);
    final customers = ref.watch(allCustomersProvider).valueOrNull ?? const [];
    final statuses = ref.watch(orderStatusesProvider).valueOrNull ?? const [];
    final allTags = ref.watch(allOrderTagsProvider).valueOrNull ?? const [];
    final customerFilter = ref.watch(orderCustomerFilterProvider);
    final filteredCustomer = customers
        .where((item) => item.id == customerFilter)
        .firstOrNull;
    final selectedTag = allTags
        .where((item) => item.id == widget.tagId)
        .firstOrNull;
    final title = switch (widget.projection) {
      OrderProjection.all => context.crmCopy('全部订单'),
      OrderProjection.important => context.crmCopy('重要订单'),
      OrderProjection.urgent => context.crmCopy('紧急订单'),
      OrderProjection.outstanding => context.crmCopy('待收款订单'),
      OrderProjection.normal => context.crmCopy('一般订单'),
      OrderProjection.tag => selectedTag?.name ?? context.crmCopy('订单标签'),
      OrderProjection.deleted => context.crmCopy('已删除'),
    };
    return SafeArea(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('export-orders'),
                    tooltip: context.crmCopy('导出 Excel'),
                    onPressed: () => showFlyExcelExport(
                      context,
                      ref,
                      origin: FlyExportOrigin.orders,
                      currentIds:
                          orders.valueOrNull?.map((item) => item.id).toSet() ??
                          <String>{},
                    ),
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                  ),
                  _OrderSortButton(
                    value: ref.watch(orderSortProvider),
                    onChanged: (value) =>
                        ref.read(orderSortProvider.notifier).state = value,
                  ),
                ],
              ),
              if (customerFilter != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    key: const ValueKey('order-customer-filter'),
                    avatar: const Icon(Icons.person_outline, size: 15),
                    label: Text(
                      '${context.crmCopy('客户')}：${filteredCustomer?.name ?? context.crmCopy('已选择客户')}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onDeleted: () =>
                        ref.read(orderCustomerFilterProvider.notifier).state =
                            null,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              const SizedBox(height: FlySpacing.sm),
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      ref.read(orderSearchProvider.notifier).state = value,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.crmCopy('搜索订单号、客户、公司、产品或工厂'),
                    prefixIcon: const Icon(Icons.search, size: 17),
                    prefixIconColor: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                    prefixIconConstraints: const BoxConstraints(minWidth: 36),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(height: FlySpacing.xs),
              const SizedBox(height: FlySpacing.xs),
              Expanded(
                child: orders.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator.adaptive()),
                  error: (error, stack) => Center(
                    child: Text(
                      context.l10n.isZh
                          ? '订单读取失败：${context.flyError(error)}'
                          : 'Unable to load orders: ${context.flyError(error)}',
                    ),
                  ),
                  data: (items) => items.isEmpty
                      ? const _EmptyOrders()
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 5),
                          itemBuilder: (context, index) {
                            final order = items[index];
                            return _OrderRow(
                              order: order,
                              customer: customers
                                  .where((item) => item.id == order.customerId)
                                  .firstOrNull,
                              status: statuses
                                  .where((item) => item.id == order.statusId)
                                  .firstOrNull,
                              selected:
                                  ref.watch(selectedOrderIdProvider) ==
                                  order.id,
                              deletedView:
                                  widget.projection == OrderProjection.deleted,
                              onSelect: () =>
                                  ref
                                      .read(selectedOrderIdProvider.notifier)
                                      .state = order
                                      .id,
                              onRestore: () => ref
                                  .read(orderRepositoryProvider)
                                  .restoreOrder(order.id),
                              onSecondaryTapDown:
                                  widget.projection == OrderProjection.deleted
                                  ? null
                                  : (details) => _showOrderDeleteMenu(
                                      order,
                                      details.globalPosition,
                                    ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.customer,
    required this.status,
    required this.selected,
    required this.deletedView,
    required this.onSelect,
    required this.onRestore,
    this.onSecondaryTapDown,
  });
  final SalesOrder order;
  final Customer? customer;
  final OrderStatusConfig? status;
  final bool selected;
  final bool deletedView;
  final VoidCallback onSelect;
  final VoidCallback onRestore;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FlyRadius.md),
        side: BorderSide(
          color: selected
              ? FlyColors.accent.withValues(alpha: .42)
              : Theme.of(context).dividerColor.withValues(alpha: .8),
        ),
      ),
      child: InkWell(
        onTap: onSelect,
        onSecondaryTapDown: onSecondaryTapDown,
        borderRadius: BorderRadius.circular(FlyRadius.md),
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              AnimatedContainer(
                duration: FlyMotion.fast,
                width: 2,
                height: selected ? 32 : 0,
                decoration: BoxDecoration(
                  color: selected ? FlyColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              if (deletedView)
                IconButton(
                  tooltip: context.crmCopy('恢复订单'),
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore, size: 18),
                ),
              Expanded(
                flex: 4,
                child: Text(
                  order.orderNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  customer?.name ?? context.crmCopy('未关联客户'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                flex: 3,
                child: status == null
                    ? Text('—')
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Color(status!.colorValue)
                                .withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status!.name,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 5),
              SizedBox(
                width: 88,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _shortDate(order.orderDate ?? order.createdAt),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (order.importance || order.urgency) ...[
                      const SizedBox(height: 3),
                      Wrap(
                        key: ValueKey('order-flags-${order.id}'),
                        spacing: 3,
                        alignment: WrapAlignment.end,
                        children: [
                          if (order.urgency)
                            _OrderFlagBadge(
                              label: context.crmCopy('紧急'),
                              color: FlyColors.warning,
                            ),
                          if (!order.urgency && order.importance)
                            _OrderFlagBadge(
                              label: context.crmCopy('重要'),
                              color: FlyColors.danger,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderFlagBadge extends StatelessWidget {
  const _OrderFlagBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: color,
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
    ),
  );
}

class _OrderSortButton extends StatelessWidget {
  const _OrderSortButton({required this.value, required this.onChanged});
  final OrderSort value;
  final ValueChanged<OrderSort> onChanged;
  @override
  Widget build(BuildContext context) => PopupMenuButton<OrderSort>(
    tooltip: context.crmCopy('排序'),
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (context) => [
      PopupMenuItem(
        value: OrderSort.createdAt,
        child: Text(context.crmCopy('创建时间')),
      ),
      PopupMenuItem(
        value: OrderSort.orderDate,
        child: Text(context.crmCopy('订单日期')),
      ),
      PopupMenuItem(
        value: OrderSort.deliveryDate,
        child: Text(context.crmCopy('交期')),
      ),
      PopupMenuItem(
        value: OrderSort.customer,
        child: Text(context.crmCopy('客户')),
      ),
      PopupMenuItem(
        value: OrderSort.status,
        child: Text(context.crmCopy('状态')),
      ),
      PopupMenuItem(
        value: OrderSort.priority,
        child: Text(context.crmCopy('优先级')),
      ),
      PopupMenuItem(
        value: OrderSort.amount,
        child: Text(context.crmCopy('金额')),
      ),
      PopupMenuItem(
        value: OrderSort.profit,
        child: Text(context.crmCopy('利润')),
      ),
      PopupMenuItem(
        value: OrderSort.manual,
        child: Text(context.crmCopy('手动')),
      ),
    ],
    child: Padding(
      padding: EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_vert, size: 18),
          SizedBox(width: 4),
          Text(context.crmCopy('排序'), style: TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();
  @override
  Widget build(BuildContext context) => WorkspaceEmptyState(
    icon: Icons.receipt_long_outlined,
    title: context.crmCopy('这里还没有订单'),
    actionLabel: context.l10n.isZh ? '从客户创建订单' : 'Create from customer',
    onCreate: () => context.go('/customers/all'),
  );
}

String _shortDate(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
