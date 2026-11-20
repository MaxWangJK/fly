import 'customer_create_dialog.dart';
import '../domain/customer_lifecycle.dart';
import '../../../l10n/service_error_copy.dart';

import 'package:flutter/material.dart';

import '../../../l10n/crm_copy.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/fly_localizations.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/destructive_action.dart';
import '../../../shared/design_system/priority.dart';
import '../../../shared/formatters/relative_date_formatter.dart';
import '../../../shared/export/fly_excel_export_action.dart';
import '../../../shared/domain/priority.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_providers.dart';
import '../../orders/presentation/order_create_dialog.dart';
import '../domain/customer.dart';
import '../import/customer_import_dialog.dart';
import 'customer_providers.dart';
import '../../../app/shell/mobile_details.dart';
import '../../../shared/design_system/responsive_layout.dart';
import '../../../shared/design_system/mobile_workspace_actions.dart';
import '../../../shared/design_system/workspace_list_columns.dart';

class CustomerListPage extends ConsumerStatefulWidget {
  const CustomerListPage({
    required this.projection,
    this.categoryId,
    super.key,
  });

  final CustomerProjection projection;
  final String? categoryId;

  @override
  ConsumerState<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends ConsumerState<CustomerListPage> {
  static const _captureContextMenu = bool.fromEnvironment(
    'FLY_CAPTURE_CUSTOMER_CONTEXT_MENU',
  );
  final _searchController = TextEditingController();
  final _followUpPending = <String>{};

  void _reconcileSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Read the current route's latest result: an older frame may have been
      // scheduled before the user switched categories or changed the search.
      final current = ref.read(
        customerListProvider((
          projection: widget.projection,
          categoryId: widget.categoryId,
        )),
      );
      if (current.isLoading || current.hasError || !current.hasValue) return;
      final visible = current.requireValue;
      final selected = ref.read(selectedCustomerIdProvider);
      if (visible.any((item) => item.id == selected)) return;
      final next = visible.firstOrNull?.id;
      if (selected != next) {
        ref.read(selectedCustomerIdProvider.notifier).state = next;
      }
      if (ref.read(customerDetailExtensionProvider) !=
          DetailExtensionType.none) {
        ref.read(customerDetailExtensionProvider.notifier).state =
            DetailExtensionType.none;
      }
    });
  }

  Future<void> _toggleFollowUp(Customer customer) async {
    if (!_followUpPending.add(customer.id)) return;
    try {
      final completed = await ref
          .read(customerRepositoryProvider)
          .toggleTodayFollowUp(customer.id);
      if (!mounted) return;
      final text = context.l10n.isZh
          ? (completed
                ? '已记录 ${customer.name} 的本次跟进'
                : '已取消 ${customer.name} 的本次跟进')
          : (completed
                ? 'Follow-up recorded for ${customer.name}'
                : 'Quick follow-up undone for ${customer.name}');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
        );
    } catch (error) {
      if (!mounted) return;
      final text =
          error is StateError && error.message == 'quickFollowUpUndoUnsafe'
          ? (context.l10n.isZh
                ? '该客户已有新的跟进记录或修改，请在跟进记录中修改。'
                : 'This customer has newer follow-ups or changes. Please edit the follow-up history.')
          : context.flyError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
    } finally {
      _followUpPending.remove(customer.id);
    }
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
          label: context.crmCopy('删除客户'),
        );
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showCustomerDeleteMenu(
    Customer customer,
    int orderCount,
    Offset position,
  ) async {
    ref.read(selectedCustomerIdProvider.notifier).state = customer.id;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'order',
          key: const ValueKey('customer-context-new-order'),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 18),
              const SizedBox(width: 8),
              Text(context.crmCopy('新建订单')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            context.crmCopy('删除客户'),
            style: const TextStyle(color: FlyColors.danger),
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'order') {
      final order = await showDialog<SalesOrder>(
        context: context,
        builder: (_) => OrderCreateDialog(
          customerId: customer.id,
          customerName: customer.name,
        ),
      );
      if (order == null || !mounted) return;
      ref.read(orderCustomerFilterProvider.notifier).state = customer.id;
      ref.read(orderSearchProvider.notifier).state = '';
      ref.read(selectedOrderIdProvider.notifier).state = order.id;
      ref.read(orderExtensionProvider.notifier).state = OrderExtensionType.none;
      context.go('/orders/all');
      return;
    }
    final confirmed = await confirmFlyDestructiveAction(
      context,
      title: context.l10n.isZh
          ? '确定删除客户“${customer.name}”？'
          : 'Delete customer “${customer.name}”?',
      message: orderCount == 0
          ? context.crmCopy('客户将进入“已删除”。')
          : (context.l10n.isZh
                ? '${customer.name} 有 $orderCount 个关联订单。\n\n'
                      '删除客户后，客户将进入“已删除”，订单不会删除。是否继续？'
                : '${customer.name} has $orderCount linked orders.\n\nThe customer will move to Deleted; orders will be retained. Continue?'),
      confirmLabel: context.crmCopy('删除客户'),
    );
    if (!confirmed) return;
    await ref.read(customerRepositoryProvider).softDeleteCustomer(customer.id);
    if (ref.read(selectedCustomerIdProvider) == customer.id) {
      ref.read(selectedCustomerIdProvider.notifier).state = null;
      ref.read(customerDetailExtensionProvider.notifier).state =
          DetailExtensionType.none;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.crmCopy('已移动到已删除'))));
  }

  String _title(List<CustomerCategory> categories) =>
      switch (widget.projection) {
        CustomerProjection.today => context.crmCopy('今天需要联系'),
        CustomerProjection.next7Days => context.crmCopy('未来7天'),
        CustomerProjection.inbox => context.crmCopy('收集箱'),
        CustomerProjection.all => context.crmCopy('全部客户'),
        CustomerProjection.deleted => context.crmCopy('已删除'),
        CustomerProjection.category =>
          categories
                  .where((item) => item.id == widget.categoryId)
                  .firstOrNull
                  ?.name ??
              context.crmCopy('客户级别'),
      };

  @override
  Widget build(BuildContext context) {
    final route = (
      projection: widget.projection,
      categoryId: widget.categoryId,
    );
    final customers = ref.watch(customerListProvider(route));
    final visibleItems = customers.valueOrNull;
    if (visibleItems != null) _reconcileSelection();
    final categories =
        ref.watch(customerCategoriesProvider).valueOrNull ?? const [];
    final statuses =
        ref.watch(allCustomerStatusesProvider).valueOrNull ?? const [];
    final allOrders =
        ref
            .watch(
              ordersProvider(const OrderQuery(projection: OrderProjection.all)),
            )
            .valueOrNull ??
        const [];
    final orderCounts = <String, int>{};
    for (final order in allOrders) {
      final customerId = order.customerId;
      if (customerId != null) {
        orderCounts[customerId] = (orderCounts[customerId] ?? 0) + 1;
      }
    }
    final canCreate = widget.projection != CustomerProjection.deleted;

    if (useCompactLayout(context)) {
      return _phoneCustomers(customers, categories, statuses);
    }

    return MobileWorkspaceActions(
      actionId: 'customer',
      query: ref.watch(customerSearchProvider),
      searchHint: context.l10n.isZh ? '搜索客户' : 'Search customers',
      onSearchChanged: (value) =>
          ref.read(customerSearchProvider.notifier).state = value,
      showSearchButton: false,
      onAdd: canCreate ? _addOnPhone : null,
      addLabel: context.l10n.isZh ? '添加客户' : 'Add customer',
      child: SafeArea(
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
                        _title(categories),
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!isMobilePlatform) ...[
                      IconButton(
                        key: const ValueKey('import-customers'),
                        tooltip: context.crmCopy('导入 Excel'),
                        onPressed: () => showDialog<Object?>(
                          context: context,
                          builder: (context) => const CustomerImportDialog(),
                        ),
                        icon: const Icon(Icons.table_view_outlined, size: 18),
                      ),
                      IconButton(
                        key: const ValueKey('export-customers'),
                        tooltip: context.crmCopy('导出 Excel'),
                        onPressed: () => showFlyExcelExport(
                          context,
                          ref,
                          origin: FlyExportOrigin.customers,
                          currentIds:
                              customers.valueOrNull
                                  ?.map((item) => item.id)
                                  .toSet() ??
                              <String>{},
                        ),
                        icon: const Icon(
                          Icons.file_download_outlined,
                          size: 18,
                        ),
                      ),
                    ],
                    _SortButton(
                      value: ref.watch(customerSortProvider),
                      onChanged: (value) =>
                          ref.read(customerSortProvider.notifier).state = value,
                    ),
                  ],
                ),
                const SizedBox(height: FlySpacing.sm),
                SizedBox(
                  height: 36,
                  child: TextField(
                    key: const ValueKey('customer-search'),
                    controller: _searchController,
                    onChanged: (value) =>
                        ref.read(customerSearchProvider.notifier).state = value,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: context.crmCopy(
                        '搜索名称、公司、Email、WhatsApp、Facebook',
                      ),
                      prefixIcon: const Icon(Icons.search, size: 17),
                      prefixIconColor: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                ref
                                        .read(customerSearchProvider.notifier)
                                        .state =
                                    '';
                                setState(() {});
                              },
                            ),
                      suffixIconConstraints: const BoxConstraints(minWidth: 34),
                    ),
                  ),
                ),
                const SizedBox(height: FlySpacing.xs),
                WorkspaceListHeader(
                  key: const ValueKey('customer-list-columns'),
                  child: WorkspaceListColumns(
                    leadingWidth: 40,
                    dateWidth: context.l10n.isZh ? 64 : 88,
                    trailingWidth: 72,
                    primary: Text(context.crmCopy('客户名称')),
                    secondary: Text(context.crmCopy('国家')),
                    status: Text(context.crmCopy('客户状态')),
                    date: Text(
                      context.crmCopy('最近跟进'),
                      textAlign: TextAlign.right,
                    ),
                    trailing: Tooltip(
                      message: context.crmCopy('下一步 / 优先级'),
                      child: Text(
                        context.crmCopy('优先级'),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: customers.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (error, stack) => Center(
                      child: Text(
                        context.l10n.isZh
                            ? '客户读取失败：${context.flyError(error)}'
                            : 'Unable to load customers: ${context.flyError(error)}',
                      ),
                    ),
                    data: (items) => items.isEmpty
                        ? const _EmptyCustomerList()
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 5),
                            itemBuilder: (context, index) => _CustomerRow(
                              customer: items[index],
                              status: statuses
                                  .where(
                                    (status) =>
                                        status.id == items[index].statusId,
                                  )
                                  .firstOrNull,
                              selected:
                                  ref.watch(selectedCustomerIdProvider) ==
                                  items[index].id,
                              deletedView:
                                  widget.projection ==
                                  CustomerProjection.deleted,
                              onSelect: () =>
                                  ref
                                      .read(selectedCustomerIdProvider.notifier)
                                      .state = items[index]
                                      .id,
                              onComplete: () => _toggleFollowUp(items[index]),
                              onRestore: () => ref
                                  .read(customerRepositoryProvider)
                                  .restoreCustomer(items[index].id),
                              onSecondaryTapDown:
                                  widget.projection ==
                                      CustomerProjection.deleted
                                  ? null
                                  : (details) => _showCustomerDeleteMenu(
                                      items[index],
                                      orderCounts[items[index].id] ?? 0,
                                      details.globalPosition,
                                    ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addOnPhone() async {
    final customer = await showDialog<Customer>(
      context: context,
      builder: (_) => CustomerCreateDialog(
        categoryId: widget.projection == CustomerProjection.category
            ? widget.categoryId
            : null,
      ),
    );
    if (!mounted || customer == null) return;
    ref.read(selectedCustomerIdProvider.notifier).state = customer.id;
    ref.read(customerSearchProvider.notifier).state = '';
    _searchController.clear();
    // Keep the sidebar projection and its linked tag after creating a customer.
    // The dialog already defaults to the current category.
  }

  Widget _phoneCustomers(
    AsyncValue<List<Customer>> customers,
    List<CustomerCategory> categories,
    List<CustomerStatus> statuses,
  ) {
    final zh = context.l10n.isZh;
    return MobileWorkspaceActions(
      actionId: 'customer',
      query: ref.watch(customerSearchProvider),
      searchHint: zh ? '搜索客户' : 'Search customers',
      onSearchChanged: (value) =>
          ref.read(customerSearchProvider.notifier).state = value,
      onAdd: widget.projection == CustomerProjection.deleted
          ? null
          : _addOnPhone,
      addLabel: zh ? '添加客户' : 'Add customer',
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final option in [
                            ('/customers/all', '全部'),
                            ('/customers/today', '今天'),
                            for (final c in categories)
                              ('/customers/category/${c.id}', c.name),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(option.$2),
                                selected:
                                    GoRouterState.of(context).uri.path ==
                                    option.$1,
                                onSelected: (_) {
                                  ref
                                          .read(
                                            customerTagFilterProvider.notifier,
                                          )
                                          .state =
                                      {};
                                  context.go(option.$1);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              WorkspaceListHeader(
                key: const ValueKey('customer-list-columns'),
                child: WorkspaceListColumns(
                  dateWidth: 64,
                  primary: Text(context.crmCopy('客户名称')),
                  secondary: Text(context.crmCopy('国家')),
                  status: Text(context.crmCopy('客户状态')),
                  date: Text(
                    context.crmCopy('最近跟进'),
                    textAlign: TextAlign.right,
                  ),
                  trailingWidth: widget.projection == CustomerProjection.deleted
                      ? 36
                      : 0,
                ),
              ),
              Expanded(
                child: customers.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator.adaptive()),
                  error: (e, _) => Center(child: Text(context.flyError(e))),
                  data: (items) => items.isEmpty
                      ? const _EmptyCustomerList()
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 184),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final customer = items[i];
                            return InkWell(
                              key: ValueKey('phone-customer-${customer.id}'),
                              onTap: () =>
                                  showCustomerDetailSheet(context, customer.id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: WorkspaceListColumns(
                                  dateWidth: 64,
                                  primary: Text(
                                    customer.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  secondary: Text(
                                    customer.country.isEmpty
                                        ? '—'
                                        : customer.country,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  status: Text(
                                    CustomerLifecycle.label(
                                      customer.statusId,
                                      zh: zh,
                                      customName: statuses
                                          .where(
                                            (s) => s.id == customer.statusId,
                                          )
                                          .firstOrNull
                                          ?.name,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  date: Text(
                                    RelativeDateFormatter.lastFollowUp(
                                      customer.lastFollowUpAt,
                                      isZh: zh,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                  trailingWidth:
                                      widget.projection ==
                                          CustomerProjection.deleted
                                      ? 36
                                      : 0,
                                  trailing:
                                      widget.projection ==
                                          CustomerProjection.deleted
                                      ? IconButton(
                                          icon: const Icon(Icons.restore),
                                          onPressed: () => ref
                                              .read(customerRepositoryProvider)
                                              .restoreCustomer(customer.id),
                                        )
                                      : null,
                                ),
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

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.status,
    required this.selected,
    required this.deletedView,
    required this.onSelect,
    required this.onComplete,
    required this.onRestore,
    this.onSecondaryTapDown,
  });
  final Customer customer;
  final CustomerStatus? status;
  final bool selected;
  final bool deletedView;
  final VoidCallback onSelect;
  final VoidCallback onComplete;
  final VoidCallback onRestore;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final followed = customer.followedUpToday(DateTime.now());
    final priorityColor = PriorityColorTokens.accent(customer.priority);
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
          height: 56,
          child: WorkspaceListColumns(
            key: ValueKey('customer-list-row-${customer.id}'),
            leadingWidth: 40,
            dateWidth: context.l10n.isZh ? 64 : 88,
            trailingWidth: 72,
            marker: AnimatedContainer(
              duration: FlyMotion.fast,
              width: 2,
              height: selected ? 30 : 0,
              decoration: BoxDecoration(
                color: selected ? FlyColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            leading: deletedView
                ? IconButton(
                    tooltip: context.crmCopy('恢复客户'),
                    onPressed: onRestore,
                    icon: const Icon(Icons.restore, size: 19),
                  )
                : Checkbox(
                    value: followed,
                    onChanged: (_) => onComplete(),
                    visualDensity: VisualDensity.compact,
                  ),
            primary: Text(
              customer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: followed
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : null,
              ),
            ),
            secondary: Text(
              customer.country.isEmpty ? '—' : customer.country,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            status: status == null
                ? Text('—')
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Color(status!.colorValue).withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        CustomerLifecycle.label(
                          customer.statusId,
                          zh: context.l10n.isZh,
                          customName: status!.name,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
            date: Text(
              RelativeDateFormatter.lastFollowUp(
                customer.lastFollowUpAt,
                isZh: context.l10n.isZh,
              ),
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (customer.nextActionType != null)
                  Container(
                    key: ValueKey('customer-next-action-${customer.id}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _nextActionColor(customer.nextActionType!)
                          .withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      customer.nextActionType!.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: _nextActionColor(customer.nextActionType!),
                      ),
                    ),
                  ),
                if (customer.nextActionType != null) const SizedBox(height: 3),
                Container(
                  key: ValueKey('customer-priority-${customer.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    switch (customer.priority) {
                      PriorityLevel.high => context.crmCopy('高'),
                      PriorityLevel.medium => context.crmCopy('中'),
                      PriorityLevel.low => context.crmCopy('一般'),
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.1,
                      color: priorityColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _nextActionColor(NextActionType type) => switch (type) {
  NextActionType.paymentFollowUp => FlyColors.warning,
  NextActionType.sendSample => const Color(0xFF4F78A8),
  NextActionType.waitingReply => const Color(0xFF6B7280),
  NextActionType.sendQuote => const Color(0xFF7B61A8),
  NextActionType.contactAgain => const Color(0xFF4D7A71),
  NextActionType.confirmOrder => FlyColors.success,
  NextActionType.other => const Color(0xFF667085),
};

class _SortButton extends StatelessWidget {
  const _SortButton({required this.value, required this.onChanged});
  final CustomerSort value;
  final ValueChanged<CustomerSort> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<CustomerSort>(
    tooltip: context.crmCopy('排序'),
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (context) => [
      PopupMenuItem(
        value: CustomerSort.todayDefault,
        child: Text(context.crmCopy('智能排序')),
      ),
      PopupMenuItem(
        value: CustomerSort.manual,
        child: Text(context.crmCopy('手动排序')),
      ),
      PopupMenuItem(
        value: CustomerSort.priority,
        child: Text(context.crmCopy('优先级')),
      ),
      PopupMenuItem(
        value: CustomerSort.nextFollowUp,
        child: Text(context.crmCopy('下次跟进')),
      ),
      PopupMenuItem(
        value: CustomerSort.lastFollowUp,
        child: Text(context.crmCopy('上次跟进')),
      ),
      PopupMenuItem(
        value: CustomerSort.createdAt,
        child: Text(context.crmCopy('创建时间')),
      ),
      PopupMenuItem(
        value: CustomerSort.name,
        child: Text(context.crmCopy('客户名称')),
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

class _EmptyCustomerList extends StatelessWidget {
  const _EmptyCustomerList();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.people_outline,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        Text(context.crmCopy('这里还没有客户')),
      ],
    ),
  );
}
