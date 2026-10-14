import '../../../l10n/service_error_copy.dart';
import '../../../l10n/fly_localizations.dart';

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../l10n/crm_copy.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/mobile_details.dart';
import '../../../shared/design_system/responsive_layout.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/detail_section_entry.dart';
import '../../../shared/design_system/extension_panel.dart';
import '../../../shared/design_system/tag_container.dart';
import '../../../shared/domain/priority.dart';
import '../../../shared/formatters/relative_date_formatter.dart';
import '../../../shared/search/fuzzy_match.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/customer_providers.dart';
import '../domain/order.dart';
import 'order_providers.dart';

class OrderDetailPanel extends ConsumerWidget {
  const OrderDetailPanel({required this.orderId, super.key});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(orderProvider(orderId));
    return value.when(
      loading: () => Center(child: CircularProgressIndicator.adaptive()),
      error: (error, stack) => Center(
        child: Text(
          (context.l10n.isZh
              ? '订单详情读取失败：${context.flyError(error)}'
              : 'Unable to load order details: ${context.flyError(error)}'),
        ),
      ),
      data: (order) {
        if (order == null) return Center(child: Text(context.crmCopy('订单不存在')));
        final statuses =
            ref.watch(orderStatusesProvider).valueOrNull ?? const [];
        final customers =
            ref.watch(allCustomersProvider).valueOrNull ?? const [];
        final tags =
            ref.watch(orderTagsProvider(order.id)).valueOrNull ?? const [];
        final allTags = ref.watch(allOrderTagsProvider).valueOrNull ?? const [];
        final items =
            ref.watch(orderItemsProvider(order.id)).valueOrNull ?? const [];
        final factories = ref.watch(factoriesProvider).valueOrNull ?? const [];
        final products = ref.watch(productsProvider).valueOrNull ?? const [];
        final payments =
            ref.watch(orderPaymentsProvider(order.id)).valueOrNull ?? const [];
        final costEntries =
            ref.watch(orderCostEntriesProvider(order.id)).valueOrNull ??
            const [];
        final files =
            ref.watch(orderFilesProvider(order.id)).valueOrNull ?? const [];
        final latestNote = ref
            .watch(latestOrderNoteProvider(order.id))
            .valueOrNull;
        final customer = customers
            .where((item) => item.id == order.customerId)
            .firstOrNull;
        final financial = OrderFinancialSummary(
          order: order,
          items: items,
          payments: payments,
          costEntries: costEntries,
        );
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 34),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _AutoSaveOrderField(
                        key: ValueKey('order-number-${order.id}'),
                        value: order.orderNumber,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: context.crmCopy('订单号'),
                        ),
                        onSave: (value) =>
                            _save(ref, order.copyWith(orderNumber: value)),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: context.crmCopy('更多'),
                      onSelected: (value) async {
                        if (value != 'delete') return;
                        final confirmed =
                            await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: Text(context.crmCopy('删除订单？')),
                                content: Text(
                                  context.crmCopy('订单会进入“已删除”，不会物理删除。'),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: Text(context.crmCopy('取消')),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: Text(context.crmCopy('移到已删除')),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                        if (confirmed) {
                          await ref
                              .read(orderRepositoryProvider)
                              .softDeleteOrder(order.id);
                          ref.read(selectedOrderIdProvider.notifier).state =
                              null;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(context.crmCopy('移到已删除')),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: FlySpacing.sm),
                _CustomerStatusRow(
                  customer: customer,
                  statuses: statuses,
                  statusId: order.statusId,
                  onStatusChanged: (value) =>
                      _save(ref, order.copyWith(statusId: value)),
                ),
                const SizedBox(height: FlySpacing.sm),
                _PriorityFlagsRow(
                  order: order,
                  onSave: (value) => _save(ref, value),
                ),
                const SizedBox(height: FlySpacing.sm),
                FlyTagContainer(
                  selected: tags
                      .map(
                        (tag) => FlyTagItem(
                          id: tag.id,
                          name: tag.name,
                          colorValue: tag.colorValue,
                        ),
                      )
                      .toList(),
                  allTags: allTags
                      .map(
                        (tag) => FlyTagItem(
                          id: tag.id,
                          name: tag.name,
                          colorValue: tag.colorValue,
                        ),
                      )
                      .toList(),
                  onChanged: (ids) => ref
                      .read(orderRepositoryProvider)
                      .setOrderTags(order.id, ids),
                  onCreate: (name) async {
                    final tag = await ref
                        .read(orderRepositoryProvider)
                        .findOrCreateTag(name);
                    return FlyTagItem(
                      id: tag.id,
                      name: tag.name,
                      colorValue: tag.colorValue,
                    );
                  },
                ),
                const SizedBox(height: FlySpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _DateButton(
                        label: context.crmCopy('订单日期'),
                        value: order.orderDate,
                        onChanged: (value) =>
                            _save(ref, order.copyWith(orderDate: value)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DateButton(
                        label: context.crmCopy('预计交期'),
                        value: order.deliveryDate,
                        onChanged: (value) =>
                            _save(ref, order.copyWith(deliveryDate: value)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FlySpacing.md),
                _OrderDetailsPreview(
                  items: items,
                  factories: factories,
                  products: products,
                  onTap: () => ref.read(orderExtensionProvider.notifier).state =
                      OrderExtensionType.orderDetails,
                ),
                const SizedBox(height: FlySpacing.sm),
                _FinancialPreview(
                  order: order,
                  summary: financial,
                  onTap: () => ref.read(orderExtensionProvider.notifier).state =
                      OrderExtensionType.financial,
                ),
                const SizedBox(height: FlySpacing.sm),
                _OrderNotePreview(
                  note: latestNote,
                  onTap: () => ref.read(orderExtensionProvider.notifier).state =
                      OrderExtensionType.notes,
                ),
                const SizedBox(height: FlySpacing.md),
                _OrderFilesSection(
                  order: order,
                  payments: payments,
                  files: files,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _save(WidgetRef ref, SalesOrder value) =>
      ref.read(orderRepositoryProvider).saveOrder(value);
}

class OrderExtensionPanel extends ConsumerStatefulWidget {
  const OrderExtensionPanel({
    required this.orderId,
    required this.type,
    required this.onClose,
    super.key,
  });

  final String orderId;
  final OrderExtensionType type;
  final VoidCallback onClose;

  @override
  ConsumerState<OrderExtensionPanel> createState() =>
      _OrderExtensionPanelState();
}

class _OrderExtensionPanelState extends ConsumerState<OrderExtensionPanel> {
  final _searchController = TextEditingController();
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  String _search = '';
  int _limit = 20;
  OrderNote? _editing;

  @override
  void initState() {
    super.initState();
    if (widget.type == OrderExtensionType.notes) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _inputFocus.requestFocus(),
      );
    }
  }

  @override
  void didUpdateWidget(covariant OrderExtensionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId || oldWidget.type != widget.type) {
      _searchController.clear();
      _inputController.clear();
      _search = '';
      _limit = 20;
      _editing = null;
      if (widget.type == OrderExtensionType.notes) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _inputFocus.requestFocus();
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _close() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onClose();
    });
  }

  Future<void> _submitNote() async {
    final content = _inputController.text.trim();
    if (content.isEmpty) return;
    final repository = ref.read(orderRepositoryProvider);
    if (_editing == null) {
      await repository.addNote(widget.orderId, content: content);
    } else {
      await repository.saveNote(_editing!.copyWith(content: content));
    }
    if (!mounted) return;
    setState(() {
      _inputController.clear();
      _editing = null;
    });
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId)).valueOrNull;
    if (order == null) return const SizedBox.shrink();
    final items =
        ref.watch(orderItemsProvider(order.id)).valueOrNull ?? const [];
    final factories = ref.watch(factoriesProvider).valueOrNull ?? const [];
    final products = ref.watch(productsProvider).valueOrNull ?? const [];
    final payments =
        ref.watch(orderPaymentsProvider(order.id)).valueOrNull ?? const [];
    final costEntries =
        ref.watch(orderCostEntriesProvider(order.id)).valueOrNull ?? const [];
    final files =
        ref.watch(orderFilesProvider(order.id)).valueOrNull ?? const [];
    final summary = OrderFinancialSummary(
      order: order,
      items: items,
      payments: payments,
      costEntries: costEntries,
    );
    final title = switch (widget.type) {
      OrderExtensionType.orderDetails => context.crmCopy('订单详情'),
      OrderExtensionType.financial => context.crmCopy('财务信息'),
      OrderExtensionType.notes => context.crmCopy('订单备注'),
      OrderExtensionType.none => '',
    };
    final notes = widget.type == OrderExtensionType.notes
        ? ref.watch(
            orderNotesProvider((
              orderId: order.id,
              search: _search,
              limit: _limit,
            )),
          )
        : null;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        elevation: FlyElevation.popup,
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            FlyExtensionHeader(
              title: title,
              onClose: _close,
              closeKey: const ValueKey('close-order-extension'),
            ),
            Expanded(
              child: switch (widget.type) {
                OrderExtensionType.orderDetails => _OrderItemsExtension(
                  orderId: order.id,
                  items: items,
                  factories: factories,
                  products: products,
                ),
                OrderExtensionType.financial => _FinancialExtension(
                  order: order,
                  summary: summary,
                  payments: payments,
                  costEntries: costEntries,
                  files: files,
                ),
                OrderExtensionType.notes => _OrderNotesExtension(
                  value: notes!,
                  searchController: _searchController,
                  inputController: _inputController,
                  inputFocus: _inputFocus,
                  search: _search,
                  editing: _editing,
                  limit: _limit,
                  onSearchChanged: (value) => setState(() {
                    _search = value.trim();
                    _limit = 20;
                  }),
                  onSubmit: _submitNote,
                  onEdit: (note) {
                    setState(() {
                      _editing = note;
                      _inputController.text = note.content;
                      _inputController.selection = TextSelection.collapsed(
                        offset: note.content.length,
                      );
                    });
                    _inputFocus.requestFocus();
                  },
                  onCancelEdit: () => setState(() {
                    _editing = null;
                    _inputController.clear();
                  }),
                  onDelete: (note) =>
                      ref.read(orderRepositoryProvider).softDeleteNote(note.id),
                  onLoadMore: () => setState(() => _limit += 20),
                ),
                OrderExtensionType.none => const SizedBox.shrink(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderItemsExtension extends ConsumerWidget {
  const _OrderItemsExtension({
    required this.orderId,
    required this.items,
    required this.factories,
    required this.products,
  });

  final String orderId;
  final List<OrderProductionItem> items;
  final List<Factory> factories;
  final List<Product> products;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('add-order-item'),
          onPressed: () => _addProductionItem(
            context,
            ref,
            orderId,
            factories: factories,
            products: products,
          ),
          icon: const Icon(Icons.add, size: 17),
          label: Text(context.crmCopy('添加项目')),
        ),
      ),
      if (items.isEmpty)
        _SoftEmpty(text: context.crmCopy('还没有项目。添加工厂、产品与数量后会显示在这里。'))
      else
        for (final item in items)
          _ExtensionProductionCard(
            item: item,
            factory: factories
                .where((entry) => entry.id == item.factoryId)
                .firstOrNull,
            product: products
                .where((entry) => entry.id == item.productId)
                .firstOrNull,
            factories: factories,
            products: products,
          ),
    ],
  );
}

class _ExtensionProductionCard extends ConsumerWidget {
  const _ExtensionProductionCard({
    required this.item,
    required this.factory,
    required this.product,
    required this.factories,
    required this.products,
  });

  final OrderProductionItem item;
  final Factory? factory;
  final Product? product;
  final List<Factory> factories;
  final List<Product> products;

  Future<void> _action(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    if (action == 'edit') {
      await _editProductionItem(
        context,
        ref,
        item.orderId,
        item: item,
        initialFactoryName: factory?.name ?? '',
        initialProductName: product?.name ?? '',
        factories: factories,
        products: products,
      );
    } else if (action == 'remove') {
      if (await _confirmFinancialDelete(
        context,
        context.crmCopy('删除这个订单项目？'),
      )) {
        await ref.read(orderRepositoryProvider).removeProductionItem(item.id);
      }
    }
  }

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'edit', child: Text(context.crmCopy('编辑项目'))),
        PopupMenuItem(value: 'remove', child: Text(context.crmCopy('删除项目'))),
      ],
    );
    if (action != null && context.mounted) await _action(context, ref, action);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    onSecondaryTapDown: (details) =>
        _showMenu(context, ref, details.globalPosition),
    child: Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 11),
      decoration: BoxDecoration(
        color: Color(item.colorValue).withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .18 : .58,
        ),
        borderRadius: BorderRadius.circular(FlyRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  factory?.name ?? context.crmCopy('未命名工厂'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product?.name ?? context.crmCopy('未命名产品'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(_quantity(item), style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 3),
                Text(
                  '${context.crmCopy('成本')} ${_money(item.factoryCost, _currencyLabel(item.factoryCostCurrency))}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: context.crmCopy('项目操作'),
            onSelected: (value) => _action(context, ref, value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(context.crmCopy('编辑项目')),
              ),
              PopupMenuItem(
                value: 'remove',
                child: Text(context.crmCopy('删除项目')),
              ),
            ],
            icon: const Icon(Icons.more_horiz, size: 17),
          ),
        ],
      ),
    ),
  );
}

class _FinancialExtension extends ConsumerWidget {
  const _FinancialExtension({
    required this.order,
    required this.summary,
    required this.payments,
    required this.costEntries,
    required this.files,
  });

  final SalesOrder order;
  final OrderFinancialSummary summary;
  final List<OrderPayment> payments;
  final List<OrderCostEntry> costEntries;
  final List<OrderFile> files;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
    children: [
      _ExchangeRateEditor(
        order: order,
        onSave: (value) => _saveOrder(ref, value),
      ),
      _FinancialGroupTitle(context.crmCopy('收入')),
      CurrencyAmountField(
        fieldKey: const ValueKey('order-sales-amount'),
        label: context.crmCopy('订单金额'),
        value: order.salesAmount,
        currency: order.currency,
        onSave: (value) => _saveOrder(
          ref,
          order.copyWith(salesAmount: value.amount, currency: value.currency),
        ),
      ),
      _FinancialGroupTitle('收款'),
      Row(
        children: [
          Expanded(
            child: _QuickFinancialEntry(
              label: '定金',
              summaryText: _sourceTotalsText(_paymentTotals(payments, '定金')),
              color: FlyColors.calendarYellow,
              onTap: () => _editPayment(
                context,
                ref,
                order,
                currency: 'USD',
                suggestedType: '定金',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickFinancialEntry(
              label: '尾款',
              summaryText: _sourceTotalsText(_paymentTotals(payments, '尾款')),
              color: FlyColors.calendarGreen,
              onTap: () => _editPayment(
                context,
                ref,
                order,
                currency: 'USD',
                suggestedType: '尾款',
              ),
            ),
          ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('add-order-payment'),
          onPressed: () => _editPayment(context, ref, order, currency: 'USD'),
          icon: const Icon(Icons.add, size: 16),
          label: Text(context.crmCopy('记录收款')),
        ),
      ),
      if (payments.isNotEmpty)
        for (final payment in payments)
          _FinancialEntryRow(
            type: payment.paymentType,
            amount: payment.amount,
            currency: payment.currency,
            date: payment.paidAt,
            attachment: files
                .where((file) => file.id == payment.attachmentId)
                .firstOrNull,
            onEdit: () => _editPayment(
              context,
              ref,
              order,
              currency: payment.currency,
              payment: payment,
            ),
            onDelete: () async {
              if (await _confirmFinancialDelete(
                context,
                context.crmCopy('删除这笔收款？'),
              )) {
                await ref
                    .read(orderRepositoryProvider)
                    .removePayment(payment.id);
              }
            },
          ),
      const SizedBox(height: 8),
      _FinancialSummaryCard(
        key: const ValueKey('received-summary'),
        label: context.crmCopy('已收合计'),
        sourceText: _sourceTotalsText(summary.receivedByCurrency),
        secondaryLabel: context.crmCopy('未收合计'),
        secondaryValue: summary.outstandingAmount == null
            ? context.crmCopy('需填写 USD → RMB 汇率')
            : _money(
                summary.outstandingAmount!,
                _currencyLabel(order.currency),
              ),
        positive: summary.isFullyPaid,
      ),
      _FinancialGroupTitle(context.crmCopy('成本与费用')),
      Row(
        children: [
          for (final value in const [
            ('工厂成本', FlyColors.calendarBlue),
            ('内陆费', FlyColors.calendarGreen),
            ('港杂费', FlyColors.calendarPink),
          ]) ...[
            Expanded(
              child: _QuickFinancialEntry(
                label: value.$1,
                summaryText: _sourceTotalsText(
                  _costTotals(costEntries, value.$1),
                ),
                color: value.$2,
                onTap: () => _editCost(
                  context,
                  ref,
                  order,
                  currency: 'CNY',
                  suggestedType: value.$1,
                ),
              ),
            ),
            if (value.$1 != '港杂费') const SizedBox(width: 7),
          ],
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('add-order-cost'),
          onPressed: () => _editCost(context, ref, order, currency: 'CNY'),
          icon: const Icon(Icons.add, size: 16),
          label: Text(context.crmCopy('新增成本')),
        ),
      ),
      if (costEntries.isNotEmpty)
        for (final entry in costEntries)
          _FinancialEntryRow(
            type: entry.costType,
            amount: entry.amountMinor,
            currency: entry.currency,
            date: entry.occurredAt,
            attachment: files
                .where((file) => file.id == entry.attachmentId)
                .firstOrNull,
            onEdit: () => _editCost(
              context,
              ref,
              order,
              currency: entry.currency,
              entry: entry,
            ),
            onDelete: () async {
              if (await _confirmFinancialDelete(
                context,
                context.crmCopy('删除这笔成本？'),
              )) {
                await ref
                    .read(orderRepositoryProvider)
                    .removeCostEntry(entry.id);
              }
            },
          ),
      const SizedBox(height: 8),
      _FinancialSummaryCard(
        key: const ValueKey('cost-summary'),
        label: context.crmCopy('成本合计'),
        sourceText: _sourceTotalsText(summary.costByCurrency),
      ),
      _FinancialGroupTitle('退税'),
      CurrencyAmountField(
        fieldKey: const ValueKey('order-tax-refund'),
        label: '退税',
        value: order.taxRefund,
        currency: order.taxRefundCurrency,
        onSave: (value) => _saveOrder(
          ref,
          order.copyWith(
            taxRefund: value.amount,
            taxRefundCurrency: value.currency,
          ),
        ),
      ),
      if (order.otherIncome != 0)
        _MoneyEditor(
          label: context.crmCopy('其他收入'),
          value: order.otherIncome,
          currency: 'RMB',
          onSave: (value) =>
              _saveOrder(ref, order.copyWith(otherIncome: value)),
        ),
      _FinancialGroupTitle(context.crmCopy('结果')),
      if (summary.profit == null)
        const _MissingRateCard()
      else ...[
        _ReadOnlyMoney(
          label: context.crmCopy('预计利润'),
          value: summary.profit!,
          currency: 'RMB',
          strong: true,
        ),
        _PlainValueRow(
          label: context.crmCopy('利润率'),
          value: summary.profitMargin == null
              ? '—'
              : '${(summary.profitMargin! * 100).toStringAsFixed(1)}%',
          strong: true,
        ),
      ],
    ],
  );
}

class _FinancialEntryRow extends ConsumerWidget {
  const _FinancialEntryRow({
    required this.type,
    required this.amount,
    required this.currency,
    required this.date,
    required this.onEdit,
    required this.onDelete,
    this.attachment,
  });

  final String type;
  final int amount;
  final String currency;
  final DateTime date;
  final OrderFile? attachment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    dense: true,
    minTileHeight: 40,
    contentPadding: EdgeInsets.zero,
    title: Text(
      '${type.isEmpty ? context.crmCopy('未分类') : type}  ${_money(amount, _currencyLabel(currency))}',
      style: const TextStyle(fontSize: 12),
    ),
    subtitle: Row(
      children: [
        Text(_date(date), style: const TextStyle(fontSize: 11)),
        if (attachment != null) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: () async {
              final path = await ref
                  .read(orderFileStorageProvider)
                  .absolutePath(attachment!.localRelativePath);
              await ref.read(orderFileOpenerProvider).open(path);
            },
            child: Text(
              (context.l10n.isZh
                  ? '附件：${attachment!.originalName}'
                  : 'Attachment: ${attachment!.originalName}'),
              style: const TextStyle(fontSize: 11, color: FlyColors.accent),
            ),
          ),
        ],
      ],
    ),
    trailing: PopupMenuButton<String>(
      tooltip: context.crmCopy('管理记录'),
      onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
      itemBuilder: (context) => [
        PopupMenuItem(value: 'edit', child: Text(context.crmCopy('编辑'))),
        PopupMenuItem(value: 'delete', child: Text(context.crmCopy('删除'))),
      ],
    ),
  );
}

class _QuickFinancialEntry extends StatelessWidget {
  const _QuickFinancialEntry({
    required this.label,
    required this.summaryText,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String summaryText;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: .72),
    borderRadius: BorderRadius.circular(FlyRadius.md),
    child: InkWell(
      key: ValueKey('quick-financial-$label'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(FlyRadius.md),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.crmCopy(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.add_rounded, size: 15),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              summaryText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ExchangeRateEditor extends StatelessWidget {
  const _ExchangeRateEditor({required this.order, required this.onSave});

  final SalesOrder order;
  final ValueChanged<SalesOrder> onSave;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('order-exchange-rate'),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(FlyRadius.sm),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.crmCopy('订单汇率'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 2),
              Text(
                context.crmCopy('1 USD = ? RMB，仅用于本订单'),
                style: TextStyle(fontSize: 10.5),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 100,
          child: _AutoSaveOrderField(
            key: ValueKey('fx-${order.exchangeRateMicros}'),
            value: order.exchangeRateMicros <= 0
                ? ''
                : (roundExchangeRateMicros(order.exchangeRateMicros) / 1000000)
                      .toStringAsFixed(2),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: context.crmCopy('如 7.12'),
              border: InputBorder.none,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onSave: (text) {
              final value = double.tryParse(text.replaceAll(',', ''));
              onSave(
                order.copyWith(
                  baseProfitCurrency: 'CNY',
                  exchangeRateMicros: value == null || value <= 0
                      ? 0
                      : roundExchangeRateMicros((value * 1000000).round()),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

typedef CurrencyAmountValue = ({int amount, String currency});

class CurrencyAmountField extends StatelessWidget {
  const CurrencyAmountField({
    required this.label,
    required this.value,
    required this.currency,
    required this.onSave,
    this.fieldKey,
    super.key,
  });

  final String label;
  final int value;
  final String currency;
  final ValueChanged<CurrencyAmountValue> onSave;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final normalized = _currencyLabel(currency) == 'RMB' ? 'CNY' : 'USD';
    return Row(
      key: fieldKey,
      children: [
        Expanded(
          child: Text(
            context.crmCopy(label),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        SizedBox(
          width: 108,
          child: _AutoSaveOrderField(
            key: ValueKey('$label-$value-$normalized'),
            value: (value / 100).toStringAsFixed(2),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
            ),
            onSave: (text) {
              final parsed = double.tryParse(text.replaceAll(',', ''));
              if (parsed != null) {
                onSave((amount: (parsed * 100).round(), currency: normalized));
              }
            },
          ),
        ),
        const SizedBox(width: 6),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'USD', label: Text('USD')),
            ButtonSegment(value: 'CNY', label: Text('RMB')),
          ],
          selected: {normalized},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity(horizontal: -3, vertical: -3),
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 10.5)),
          ),
          onSelectionChanged: (values) =>
              onSave((amount: value, currency: values.first)),
        ),
      ],
    );
  }
}

class _FinancialSummaryCard extends StatelessWidget {
  const _FinancialSummaryCard({
    required this.label,
    required this.sourceText,
    this.secondaryLabel,
    this.secondaryValue,
    this.positive = false,
    super.key,
  });

  final String label;
  final String sourceText;
  final String? secondaryLabel;
  final String? secondaryValue;
  final bool positive;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: (positive ? FlyColors.success : FlyColors.accent).withValues(
        alpha: .08,
      ),
      borderRadius: BorderRadius.circular(FlyRadius.sm),
      border: Border.all(
        color: (positive ? FlyColors.success : FlyColors.accent).withValues(
          alpha: .18,
        ),
      ),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.crmCopy(label),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              sourceText.isEmpty ? '—' : sourceText,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        if (secondaryLabel != null && secondaryValue != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  secondaryLabel!,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              Flexible(
                child: Text(
                  secondaryValue!,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: positive ? FlyColors.success : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _MissingRateCard extends StatelessWidget {
  const _MissingRateCard();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('profit-rate-required'),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: FlyColors.warning.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(FlyRadius.sm),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: FlyColors.warning),
        SizedBox(width: 7),
        Expanded(
          child: Text(
            context.crmCopy('包含 USD 金额，请填写本订单 USD → RMB 汇率后计算利润。'),
            style: TextStyle(fontSize: 11.5),
          ),
        ),
      ],
    ),
  );
}

class _FinancialGroupTitle extends StatelessWidget {
  const _FinancialGroupTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 5),
    child: Text(
      context.crmCopy(title),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

class _PlainValueRow extends StatelessWidget {
  const _PlainValueRow({
    required this.label,
    required this.value,
    this.strong = false,
  });
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            context.crmCopy(label),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _OrderNotesExtension extends StatelessWidget {
  const _OrderNotesExtension({
    required this.value,
    required this.searchController,
    required this.inputController,
    required this.inputFocus,
    required this.search,
    required this.editing,
    required this.limit,
    required this.onSearchChanged,
    required this.onSubmit,
    required this.onEdit,
    required this.onCancelEdit,
    required this.onDelete,
    required this.onLoadMore,
  });

  final AsyncValue<List<OrderNote>> value;
  final TextEditingController searchController;
  final TextEditingController inputController;
  final FocusNode inputFocus;
  final String search;
  final OrderNote? editing;
  final int limit;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSubmit;
  final ValueChanged<OrderNote> onEdit;
  final VoidCallback onCancelEdit;
  final ValueChanged<OrderNote> onDelete;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: TextField(
          key: const ValueKey('order-note-search'),
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 17),
            hintText: context.crmCopy('搜索订单备注…'),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(FlyRadius.md),
          ),
          child: Column(
            children: [
              FlySubmitOnEnter(
                onSubmit: onSubmit,
                child: TextField(
                  key: const ValueKey('new-order-note-input'),
                  controller: inputController,
                  focusNode: inputFocus,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: editing == null
                        ? context.crmCopy('记录订单注意事项…')
                        : context.crmCopy('编辑这条订单备注…'),
                  ),
                ),
              ),
              Row(
                children: [
                  if (editing != null)
                    TextButton(
                      onPressed: onCancelEdit,
                      child: Text(context.crmCopy('取消编辑')),
                    ),
                  const Spacer(),
                  Text(
                    context.crmCopy('Enter 保存 · Shift+Enter 换行'),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: value.when(
          loading: () => Center(child: CircularProgressIndicator.adaptive()),
          error: (error, stack) => Center(
            child: Text(
              (context.l10n.isZh
                  ? '订单备注读取失败：${context.flyError(error)}'
                  : 'Unable to load order notes: ${context.flyError(error)}'),
            ),
          ),
          data: (notes) => notes.isEmpty
              ? Center(
                  child: Text(
                    context.crmCopy('还没有订单备注。'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    for (final note in notes)
                      GestureDetector(
                        onDoubleTap: () => onEdit(note),
                        child: FlyHistoryBlock(
                          color: Color(note.colorValue),
                          meta:
                              '${RelativeDateFormatter.dateTime(note.createdAt, isZh: context.l10n.isZh)}${note.updatedAt.difference(note.createdAt).inSeconds.abs() > 1 ? (context.l10n.isZh ? ' · 已编辑' : ' · Edited') : ''}',
                          content: note.content,
                          menu: PopupMenuButton<String>(
                            tooltip: context.crmCopy('备注操作'),
                            onSelected: (value) =>
                                value == 'edit' ? onEdit(note) : onDelete(note),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(context.crmCopy('编辑')),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(context.crmCopy('删除')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (notes.length >= limit)
                      TextButton(
                        onPressed: onLoadMore,
                        child: Text(context.crmCopy('加载更多')),
                      ),
                  ],
                ),
        ),
      ),
    ],
  );
}

class _CustomerStatusRow extends ConsumerWidget {
  const _CustomerStatusRow({
    required this.customer,
    required this.statuses,
    required this.statusId,
    required this.onStatusChanged,
  });
  final Customer? customer;
  final List<OrderStatusConfig> statuses;
  final String? statusId;
  final ValueChanged<String?> onStatusChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: [
      Expanded(
        child: _CompactField(
          label: context.crmCopy('客户'),
          child: InkWell(
            key: const ValueKey('order-customer-link'),
            onTap: customer == null
                ? null
                : () {
                    ref.read(selectedCustomerIdProvider.notifier).state =
                        customer!.id;
                    ref.read(orderExtensionProvider.notifier).state =
                        OrderExtensionType.none;
                    if (useCompactLayout(context)) {
                      final navigator = Navigator.of(context);
                      final router = GoRouter.of(context);
                      navigator.pop();
                      router.go('/customers/all');
                      final sheetContext = navigator.context;
                      if (sheetContext.mounted) {
                        showCustomerDetailSheet(sheetContext, customer!.id);
                      }
                    } else {
                      context.go('/customers/all');
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                customer == null
                    ? context.crmCopy('未关联客户')
                    : '${customer!.name} ›',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _CompactField(
          label: context.crmCopy('订单状态'),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: statusId,
              isDense: true,
              isExpanded: true,
              items: [
                for (final status in statuses)
                  DropdownMenuItem(value: status.id, child: Text(status.name)),
              ],
              onChanged: onStatusChanged,
            ),
          ),
        ),
      ),
    ],
  );
}

class _CompactField extends StatelessWidget {
  const _CompactField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(FlyRadius.sm),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.crmCopy(label),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        child,
      ],
    ),
  );
}

class _PriorityFlagsRow extends StatelessWidget {
  const _PriorityFlagsRow({required this.order, required this.onSave});

  final SalesOrder order;
  final ValueChanged<SalesOrder> onSave;

  @override
  Widget build(BuildContext context) {
    final selected = order.urgency
        ? 'urgent'
        : order.importance
        ? 'important'
        : 'normal';
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(context.crmCopy('级别'), style: TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: SegmentedButton<String>(
            key: const ValueKey('order-level-selector'),
            segments: [
              ButtonSegment(
                value: 'normal',
                label: Text(context.crmCopy('一般')),
              ),
              ButtonSegment(
                value: 'important',
                label: Text(context.crmCopy('重要')),
              ),
              ButtonSegment(
                value: 'urgent',
                label: Text(context.crmCopy('紧急')),
              ),
            ],
            selected: {selected},
            showSelectedIcon: true,
            style: const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -2, vertical: -2),
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11.5)),
            ),
            onSelectionChanged: (values) {
              final value = values.first;
              onSave(
                order.copyWith(
                  priority: PriorityLevel.low,
                  importance: value == 'important',
                  urgency: value == 'urgent',
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OrderDetailsPreview extends StatelessWidget {
  const _OrderDetailsPreview({
    required this.items,
    required this.factories,
    required this.products,
    required this.onTap,
  });

  final List<OrderProductionItem> items;
  final List<Factory> factories;
  final List<Product> products;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    String factoryName(OrderProductionItem item) =>
        factories
            .where((factory) => factory.id == item.factoryId)
            .firstOrNull
            ?.name ??
        context.crmCopy('未命名工厂');
    String productName(OrderProductionItem item) =>
        products
            .where((product) => product.id == item.productId)
            .firstOrNull
            ?.name ??
        context.crmCopy('未命名产品');
    return DetailSectionEntry(
      key: const ValueKey('order-details-preview'),
      title: context.crmCopy('订单详情'),
      icon: Icons.inventory_2_outlined,
      onTap: onTap,
      preview: items.isEmpty
          ? Text(
              context.crmCopy('添加工厂、产品和数量'),
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in items.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${factoryName(item)} · ${productName(item)} · ${_quantity(item)} · '
                      '${_money(item.factoryCost, _currencyLabel(item.factoryCostCurrency))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (items.length > 3)
                  Text(
                    '+${items.length - 3}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
    );
  }
}

class _FinancialPreview extends StatelessWidget {
  const _FinancialPreview({
    required this.order,
    required this.summary,
    required this.onTap,
  });

  final SalesOrder order;
  final OrderFinancialSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DetailSectionEntry(
    key: const ValueKey('order-financial-preview'),
    title: context.crmCopy('财务信息'),
    icon: Icons.account_balance_wallet_outlined,
    onTap: onTap,
    preview: Row(
      children: [
        _PreviewMetric(
          label: context.crmCopy('订单金额'),
          value: _money(order.salesAmount, order.currency),
        ),
        _PreviewMetric(
          label: context.crmCopy('预计利润'),
          value: summary.profit == null
              ? context.crmCopy('需填写汇率')
              : _money(summary.profit!, 'RMB'),
        ),
        _PreviewMetric(
          label: context.crmCopy('未收金额'),
          value: summary.outstandingAmount == null
              ? '—'
              : _money(summary.outstandingAmount!, order.currency),
        ),
      ],
    ),
  );
}

class _OrderNotePreview extends StatelessWidget {
  const _OrderNotePreview({required this.note, required this.onTap});

  final OrderNote? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DetailSectionEntry(
    key: const ValueKey('order-notes-preview'),
    title: context.crmCopy('订单备注'),
    icon: Icons.sticky_note_2_outlined,
    onTap: onTap,
    preview: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          note?.content ?? context.crmCopy('记录包装、交期风险和客户特殊要求'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, height: 1.35),
        ),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(
            RelativeDateFormatter.dateTime(
              note!.createdAt,
              isZh: context.l10n.isZh,
            ),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ],
    ),
  );
}

class _PreviewMetric extends StatelessWidget {
  const _PreviewMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.crmCopy(label),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final selected = await showDatePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDate: value ?? DateTime.now(),
      );
      if (selected != null) onChanged(selected);
    },
    borderRadius: BorderRadius.circular(FlyRadius.sm),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(FlyRadius.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value == null ? label : '$label  ${_date(value!)}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          if (value != null)
            InkWell(
              onTap: () => onChanged(null),
              child: const Icon(Icons.close, size: 14),
            ),
        ],
      ),
    ),
  );
}

class _OrderFilesSection extends ConsumerStatefulWidget {
  const _OrderFilesSection({
    required this.order,
    required this.payments,
    required this.files,
  });
  final SalesOrder order;
  final List<OrderPayment> payments;
  final List<OrderFile> files;
  @override
  ConsumerState<_OrderFilesSection> createState() => _OrderFilesSectionState();
}

class _OrderFilesSectionState extends ConsumerState<_OrderFilesSection> {
  bool _dragging = false;

  Future<void> _pickFiles() async {
    final files = await openFiles();
    for (final file in files) {
      await _import(file.path, askType: true);
    }
  }

  Future<void> _import(String path, {required bool askType}) async {
    var type = OrderDocumentType.other;
    String? paymentId;
    if (askType && mounted) {
      final selection = await _chooseFileType(context, widget.payments);
      if (selection == null) return;
      type = selection.type;
      paymentId = selection.paymentId;
    }
    final stored = await ref
        .read(orderFileStorageProvider)
        .importFile(
          sourcePath: path,
          orderId: widget.order.id,
          documentType: type,
        );
    await ref
        .read(orderRepositoryProvider)
        .addFileMetadata(
          orderId: widget.order.id,
          paymentId: paymentId,
          fileName: stored.fileName,
          originalName: stored.originalName,
          documentType: type,
          localRelativePath: stored.relativePath,
          fileSize: stored.fileSize,
          mimeType: stored.mimeType,
        );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <OrderDocumentType, List<OrderFile>>{};
    for (final file in widget.files) {
      (grouped[file.documentType] ??= []).add(file);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: context.crmCopy('文件管理'),
          action: TextButton.icon(
            onPressed: _pickFiles,
            icon: const Icon(Icons.upload_file_outlined, size: 17),
            label: Text(context.crmCopy('上传文件')),
          ),
        ),
        DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (details) async {
            setState(() => _dragging = false);
            for (final item in details.files.whereType<DropItemFile>()) {
              await _import(item.path, askType: true);
            }
          },
          child: AnimatedContainer(
            duration: FlyMotion.standard,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _dragging ? FlyColors.accentSoft : Colors.transparent,
              border: Border.all(
                color: _dragging
                    ? FlyColors.accent
                    : Theme.of(context).dividerColor,
              ),
              borderRadius: BorderRadius.circular(FlyRadius.md),
            ),
            child: Text(
              _dragging
                  ? context.crmCopy('松开以添加到订单')
                  : context.crmCopy('拖放 PI / CI / PL / CO / 转账记录或其他文件'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (widget.files.isEmpty)
          _SoftEmpty(text: context.crmCopy('文件保存到 FlyData，SQLite 只记录元数据。'))
        else
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 3),
              child: Text(
                context.crmCopy(_documentType(entry.key)),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final file in entry.value) _FileTile(file: file),
          ],
      ],
    );
  }
}

class _FileTile extends ConsumerWidget {
  const _FileTile({required this.file});
  final OrderFile file;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    dense: true,
    minTileHeight: 38,
    contentPadding: EdgeInsets.zero,
    leading: Icon(_fileIcon(file.fileName), size: 18),
    title: Text(
      file.originalName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12),
    ),
    subtitle: Text(
      _fileSize(file.fileSize),
      style: const TextStyle(fontSize: 10),
    ),
    onTap: () async {
      final path = await ref
          .read(orderFileStorageProvider)
          .absolutePath(file.localRelativePath);
      await ref.read(orderFileOpenerProvider).open(path);
    },
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<OrderDocumentType>(
            value: file.documentType,
            isDense: true,
            items: OrderDocumentType.values
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(
                      context.crmCopy(_documentType(value)),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                ref
                    .read(orderRepositoryProvider)
                    .changeFileDocumentType(file.id, value);
              }
            },
          ),
        ),
        IconButton(
          tooltip: context.crmCopy('删除文件'),
          onPressed: () async {
            await ref
                .read(orderFileStorageProvider)
                .removeStoredFile(file.localRelativePath);
            await ref.read(orderRepositoryProvider).removeFile(file.id);
          },
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  );
}

class _MoneyEditor extends StatelessWidget {
  const _MoneyEditor({
    required this.label,
    required this.value,
    required this.currency,
    required this.onSave,
  });
  final String label;
  final int value;
  final String currency;
  final ValueChanged<int> onSave;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          context.crmCopy(label),
          style: const TextStyle(fontSize: 12),
        ),
      ),
      SizedBox(
        width: 132,
        child: _AutoSaveOrderField(
          key: ValueKey('$label-$value'),
          value: (value / 100).toStringAsFixed(2),
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            isDense: true,
            prefixText: '$currency ',
            border: InputBorder.none,
          ),
          onSave: (text) {
            final parsed = double.tryParse(text.replaceAll(',', ''));
            if (parsed != null) onSave((parsed * 100).round());
          },
        ),
      ),
    ],
  );
}

class _ReadOnlyMoney extends StatelessWidget {
  const _ReadOnlyMoney({
    required this.label,
    required this.value,
    required this.currency,
    this.strong = false,
  });
  final String label;
  final int value;
  final String currency;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            context.crmCopy(label),
            style: TextStyle(
              fontSize: 12,
              fontWeight: strong ? FontWeight.w700 : null,
            ),
          ),
        ),
        Text(
          _money(value, currency),
          style: TextStyle(
            fontSize: 12,
            fontWeight: strong ? FontWeight.w800 : null,
          ),
        ),
      ],
    ),
  );
}

class _AutoSaveOrderField extends StatefulWidget {
  const _AutoSaveOrderField({
    required this.value,
    required this.onSave,
    required this.decoration,
    this.style,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    super.key,
  });
  final String value;
  final ValueChanged<String> onSave;
  final InputDecoration decoration;
  final TextStyle? style;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  @override
  State<_AutoSaveOrderField> createState() => _AutoSaveOrderFieldState();
}

class _AutoSaveOrderFieldState extends State<_AutoSaveOrderField> {
  late final TextEditingController _controller;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _AutoSaveOrderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        _controller.text == oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    style: widget.style,
    maxLines: 1,
    textAlign: widget.textAlign,
    decoration: widget.decoration,
    inputFormatters: widget.inputFormatters,
    onChanged: (value) {
      _timer?.cancel();
      _timer = Timer(FlyMotion.autoSave, () => widget.onSave(value.trim()));
    },
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            context.crmCopy(title),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class _SoftEmpty extends StatelessWidget {
  const _SoftEmpty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(FlyRadius.sm),
    ),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

Future<void> _saveOrder(WidgetRef ref, SalesOrder order) =>
    ref.read(orderRepositoryProvider).saveOrder(order);

Future<void> _addProductionItem(
  BuildContext context,
  WidgetRef ref,
  String orderId, {
  required List<Factory> factories,
  required List<Product> products,
}) => _editProductionItem(
  context,
  ref,
  orderId,
  factories: factories,
  products: products,
);

Future<void> _editProductionItem(
  BuildContext context,
  WidgetRef ref,
  String orderId, {
  required List<Factory> factories,
  required List<Product> products,
  OrderProductionItem? item,
  String initialFactoryName = '',
  String initialProductName = '',
}) async {
  final factory = TextEditingController(text: initialFactoryName);
  final product = TextEditingController(text: initialProductName);
  final quantity = TextEditingController(
    text: item == null
        ? '1'
        : (item.quantityMilli / 1000).toStringAsFixed(
            item.quantityMilli % 1000 == 0 ? 0 : 3,
          ),
  );
  final unit = TextEditingController(text: item?.unit ?? 'pcs');
  final cost = TextEditingController(
    text: item == null ? '' : (item.factoryCost / 100).toStringAsFixed(2),
  );
  final factoryFocus = FocusNode();
  final productFocus = FocusNode();
  final quantityFocus = FocusNode();
  String? validationMessage;
  var costCurrency = item?.factoryCostCurrency ?? 'CNY';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          item == null ? context.crmCopy('添加订单项目') : context.crmCopy('编辑订单项目'),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RawAutocomplete<String>(
                textEditingController: factory,
                focusNode: factoryFocus,
                optionsBuilder: (value) => value.text.trim().isEmpty
                    ? const Iterable<String>.empty()
                    : factories
                          .map((item) => item.name)
                          .where(
                            (name) => FuzzyMatch.matches(value.text, [name]),
                          ),
                onSelected: (value) => factory.text = value,
                fieldViewBuilder:
                    (context, controller, focusNode, onSubmitted) => TextField(
                      key: const ValueKey('order-item-factory'),
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      onSubmitted: (value) async {
                        if (value.trim().isNotEmpty) {
                          await ref
                              .read(orderRepositoryProvider)
                              .findOrCreateFactory(value.trim());
                          productFocus.requestFocus();
                        }
                      },
                      decoration: InputDecoration(
                        labelText: context.crmCopy('工厂 *'),
                        hintText: context.crmCopy('搜索；Enter 创建'),
                      ),
                    ),
                optionsViewBuilder: (context, onSelected, options) =>
                    _AutocompleteOptions(
                      options: options,
                      onSelected: onSelected,
                    ),
              ),
              const SizedBox(height: 16),
              RawAutocomplete<String>(
                textEditingController: product,
                focusNode: productFocus,
                optionsBuilder: (value) => value.text.trim().isEmpty
                    ? const Iterable<String>.empty()
                    : products
                          .map((item) => item.name)
                          .where(
                            (name) => FuzzyMatch.matches(value.text, [name]),
                          ),
                onSelected: (value) => product.text = value,
                fieldViewBuilder:
                    (context, controller, focusNode, onSubmitted) => TextField(
                      key: const ValueKey('order-item-product'),
                      controller: controller,
                      focusNode: focusNode,
                      onSubmitted: (value) async {
                        if (value.trim().isNotEmpty) {
                          await ref
                              .read(orderRepositoryProvider)
                              .findOrCreateProduct(
                                value.trim(),
                                unit: unit.text.trim().isEmpty
                                    ? 'pcs'
                                    : unit.text.trim(),
                              );
                          quantityFocus.requestFocus();
                        }
                      },
                      decoration: InputDecoration(
                        labelText: context.crmCopy('产品 *'),
                        hintText: context.crmCopy('搜索；Enter 创建'),
                      ),
                    ),
                optionsViewBuilder: (context, onSelected, options) =>
                    _AutocompleteOptions(
                      options: options,
                      onSelected: onSelected,
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('order-item-quantity'),
                      controller: quantity,
                      focusNode: quantityFocus,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.crmCopy('数量 *'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('order-item-unit'),
                      controller: unit,
                      decoration: InputDecoration(
                        labelText: context.crmCopy('单位'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('order-item-cost'),
                      controller: cost,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.crmCopy('工厂成本（可选）'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<String>(
                    key: const ValueKey('order-item-cost-currency'),
                    segments: [
                      ButtonSegment(value: 'USD', label: Text('USD')),
                      ButtonSegment(value: 'CNY', label: Text('RMB')),
                    ],
                    selected: {costCurrency},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) =>
                        setDialogState(() => costCurrency = value.first),
                  ),
                ],
              ),
              if (validationMessage != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      validationMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: FlyColors.danger,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.crmCopy('取消')),
          ),
          FilledButton(
            key: const ValueKey('save-order-item'),
            onPressed: () {
              final qty = double.tryParse(quantity.text.trim());
              if (factory.text.trim().isEmpty ||
                  product.text.trim().isEmpty ||
                  qty == null ||
                  qty <= 0) {
                setDialogState(
                  () => validationMessage = context.crmCopy(
                    '工厂、产品和大于 0 的数量均为必填。',
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: Text(
              item == null ? context.crmCopy('添加') : context.crmCopy('保存'),
            ),
          ),
        ],
      ),
    ),
  );
  if (confirmed == true) {
    final qty = double.parse(quantity.text);
    final costMinor = ((double.tryParse(cost.text) ?? 0) * 100).round();
    final repository = ref.read(orderRepositoryProvider);
    final unitValue = unit.text.trim().isEmpty ? 'pcs' : unit.text.trim();
    if (item == null) {
      await repository.addProductionItem(
        orderId,
        factoryName: factory.text.trim(),
        productName: product.text.trim(),
        quantityMilli: (qty * 1000).round(),
        unit: unitValue,
        factoryCost: costMinor,
        factoryCostCurrency: costCurrency,
      );
    } else {
      await repository.saveProductionItem(
        item.copyWith(
          quantityMilli: (qty * 1000).round(),
          unit: unitValue,
          factoryCost: costMinor,
          factoryCostCurrency: costCurrency,
        ),
        factoryName: factory.text.trim(),
        productName: product.text.trim(),
      );
    }
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final controller in [factory, product, quantity, unit, cost]) {
      controller.dispose();
    }
    for (final focus in [factoryFocus, productFocus, quantityFocus]) {
      focus.dispose();
    }
  });
}

class _AutocompleteOptions extends StatelessWidget {
  const _AutocompleteOptions({required this.options, required this.onSelected});
  final Iterable<String> options;
  final AutocompleteOnSelected<String> onSelected;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: Material(
      elevation: FlyElevation.popup,
      borderRadius: BorderRadius.circular(FlyRadius.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 160),
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: [
            for (final option in options)
              ListTile(
                dense: true,
                title: Text(option),
                onTap: () => onSelected(option),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _editPayment(
  BuildContext context,
  WidgetRef ref,
  SalesOrder order, {
  required String currency,
  OrderPayment? payment,
  String? suggestedType,
}) async {
  final draft = await showDialog<_FinancialEntryDraft>(
    context: context,
    builder: (_) => _FinancialEntryDialog(
      title: payment == null
          ? context.crmCopy('记录收款')
          : context.crmCopy('编辑收款'),
      currency: currency,
      initialAmount: payment?.amount,
      initialType: payment?.paymentType ?? suggestedType ?? '',
      typeHint: context.crmCopy('定金 / 尾款 / 补款 / 样品费…'),
      initialDate: payment?.paidAt,
    ),
  );
  if (draft == null) return;
  final repository = ref.read(orderRepositoryProvider);
  var saved = payment == null
      ? await repository.addPayment(
          order.id,
          amount: draft.amountMinor,
          currency: draft.currency,
          paymentType: draft.type,
          paidAt: draft.date,
        )
      : payment.copyWith(
          amount: draft.amountMinor,
          currency: draft.currency,
          paymentType: draft.type,
          paidAt: draft.date,
        );
  if (payment != null) await repository.savePayment(saved);
  if (draft.sourcePath != null) {
    final attachment = await _storeFinancialAttachment(
      ref,
      order,
      draft.sourcePath!,
      OrderDocumentType.payment,
      paymentId: saved.id,
    );
    saved = saved.copyWith(attachmentId: attachment.id);
    await repository.savePayment(saved);
  }
}

Future<void> _editCost(
  BuildContext context,
  WidgetRef ref,
  SalesOrder order, {
  required String currency,
  OrderCostEntry? entry,
  String? suggestedType,
}) async {
  final draft = await showDialog<_FinancialEntryDraft>(
    context: context,
    builder: (_) => _FinancialEntryDialog(
      title: entry == null ? context.crmCopy('新增成本') : context.crmCopy('编辑成本'),
      currency: currency,
      initialAmount: entry?.amountMinor,
      initialType: entry?.costType ?? suggestedType ?? '',
      typeHint: context.crmCopy('工厂成本 / 内陆费 / 港杂费 / 拖车费 / 报关费…'),
      initialDate: entry?.occurredAt,
    ),
  );
  if (draft == null) return;
  final repository = ref.read(orderRepositoryProvider);
  var saved = entry == null
      ? await repository.addCostEntry(
          order.id,
          amountMinor: draft.amountMinor,
          currency: draft.currency,
          costType: draft.type,
          occurredAt: draft.date,
        )
      : entry.copyWith(
          amountMinor: draft.amountMinor,
          currency: draft.currency,
          costType: draft.type,
          occurredAt: draft.date,
        );
  if (entry != null) await repository.saveCostEntry(saved);
  if (draft.sourcePath != null) {
    final attachment = await _storeFinancialAttachment(
      ref,
      order,
      draft.sourcePath!,
      OrderDocumentType.other,
    );
    saved = saved.copyWith(attachmentId: attachment.id);
    await repository.saveCostEntry(saved);
  }
}

Future<OrderFile> _storeFinancialAttachment(
  WidgetRef ref,
  SalesOrder order,
  String sourcePath,
  OrderDocumentType type, {
  String? paymentId,
}) async {
  final stored = await ref
      .read(orderFileStorageProvider)
      .importFile(
        sourcePath: sourcePath,
        orderId: order.id,
        documentType: type,
      );
  return ref
      .read(orderRepositoryProvider)
      .addFileMetadata(
        orderId: order.id,
        paymentId: paymentId,
        fileName: stored.fileName,
        originalName: stored.originalName,
        documentType: type,
        localRelativePath: stored.relativePath,
        fileSize: stored.fileSize,
        mimeType: stored.mimeType,
      );
}

Future<bool> _confirmFinancialDelete(BuildContext context, String title) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(context.crmCopy('删除后不会计入财务汇总。')),
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
      ) ??
      false;
}

class _FinancialEntryDraft {
  const _FinancialEntryDraft({
    required this.amountMinor,
    required this.type,
    required this.date,
    required this.currency,
    this.sourcePath,
  });
  final int amountMinor;
  final String type;
  final DateTime date;
  final String currency;
  final String? sourcePath;
}

class _FinancialEntryDialog extends StatefulWidget {
  const _FinancialEntryDialog({
    required this.title,
    required this.currency,
    required this.initialType,
    required this.typeHint,
    this.initialAmount,
    this.initialDate,
  });

  final String title;
  final String currency;
  final int? initialAmount;
  final String initialType;
  final String typeHint;
  final DateTime? initialDate;

  @override
  State<_FinancialEntryDialog> createState() => _FinancialEntryDialogState();
}

class _FinancialEntryDialogState extends State<_FinancialEntryDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _type;
  late DateTime _occurredAt;
  late String _currency;
  String? _sourcePath;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.initialAmount == null
          ? ''
          : (widget.initialAmount! / 100).toStringAsFixed(2),
    );
    _type = TextEditingController(text: widget.initialType);
    _occurredAt = widget.initialDate ?? DateTime.now();
    _currency = _currencyLabel(widget.currency) == 'RMB' ? 'CNY' : 'USD';
  }

  @override
  void dispose() {
    _amount.dispose();
    _type.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    final file = await openFile();
    if (file != null) setState(() => _sourcePath = file.path);
  }

  void _save() {
    final parsed = double.tryParse(_amount.text.replaceAll(',', ''));
    final type = _type.text.trim();
    if (parsed == null || parsed <= 0 || type.isEmpty) return;
    Navigator.pop(
      context,
      _FinancialEntryDraft(
        amountMinor: (parsed * 100).round(),
        type: type,
        date: _occurredAt,
        currency: _currency,
        sourcePath: _sourcePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
    contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
    actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
    title: Text(
      widget.title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EntryFieldLabel(context.crmCopy('金额')),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('financial-entry-amount'),
                  controller: _amount,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(hintText: '0.00'),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                key: const ValueKey('financial-entry-currency'),
                segments: [
                  ButtonSegment(value: 'USD', label: Text('USD')),
                  ButtonSegment(value: 'CNY', label: Text('RMB')),
                ],
                selected: {_currency},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => _currency = value.first),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _EntryFieldLabel(context.crmCopy('类型')),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('financial-entry-type'),
            controller: _type,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(hintText: widget.typeHint),
          ),
          const SizedBox(height: 16),
          _EntryFieldLabel(context.crmCopy('时间')),
          const SizedBox(height: 6),
          ListTile(
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(FlyRadius.sm),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            minTileHeight: 44,
            title: Text(_dateText, style: const TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.event_outlined, size: 18),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                initialDate: _occurredAt,
              );
              if (picked != null) setState(() => _occurredAt = picked);
            },
          ),
          const SizedBox(height: 16),
          _EntryFieldLabel(context.crmCopy('文件')),
          const SizedBox(height: 6),
          DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (details) {
              final file = details.files.whereType<DropItemFile>().firstOrNull;
              setState(() {
                _dragging = false;
                _sourcePath = file?.path;
              });
            },
            child: InkWell(
              key: const ValueKey('financial-entry-attachment'),
              onTap: _pickAttachment,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _dragging ? FlyColors.accentSoft : Colors.transparent,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(FlyRadius.sm),
                ),
                child: Text(
                  _sourcePath == null
                      ? context.crmCopy('上传文件或截图（也可拖入）')
                      : '附件：${_sourcePath!.split(RegExp(r'[/\\]')).last}',
                  style: TextStyle(
                    fontSize: 13,
                    color: _sourcePath == null
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.crmCopy('取消')),
      ),
      FilledButton(onPressed: _save, child: Text(context.crmCopy('保存'))),
    ],
  );

  String get _dateText => _date(_occurredAt);
}

class _EntryFieldLabel extends StatelessWidget {
  const _EntryFieldLabel(this.value);
  final String value;

  @override
  Widget build(BuildContext context) => Text(
    value,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  );
}

typedef _FileSelection = ({OrderDocumentType type, String? paymentId});
Future<_FileSelection?> _chooseFileType(
  BuildContext context,
  List<OrderPayment> payments,
) async {
  var type = OrderDocumentType.other;
  String? paymentId;
  return showDialog<_FileSelection>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.crmCopy('文件分类')),
        content: SizedBox(
          width: 330,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<OrderDocumentType>(
                initialValue: type,
                decoration: InputDecoration(labelText: context.crmCopy('分类')),
                items: OrderDocumentType.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(context.crmCopy(_documentType(value))),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => type = value ?? type),
              ),
              if (payments.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: paymentId,
                  decoration: InputDecoration(
                    labelText: context.crmCopy('关联收款（可选）'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(context.crmCopy('不关联')),
                    ),
                    ...payments.map(
                      (payment) => DropdownMenuItem(
                        value: payment.id,
                        child: Text(
                          '${_date(payment.paidAt)} · ${_money(payment.amount, payment.currency)}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setDialogState(() => paymentId = value),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.crmCopy('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, (
              type: type,
              paymentId: paymentId,
            )),
            child: Text(context.crmCopy('保存')),
          ),
        ],
      ),
    ),
  );
}

Map<String, int> _paymentTotals(List<OrderPayment> values, String type) {
  final result = <String, int>{};
  for (final entry in values.where(
    (entry) => entry.paymentType.trim() == type,
  )) {
    final currency = _currencyLabel(entry.currency);
    result[currency] = (result[currency] ?? 0) + entry.amount;
  }
  return result;
}

Map<String, int> _costTotals(List<OrderCostEntry> values, String type) {
  final result = <String, int>{};
  for (final entry in values.where((entry) => entry.costType.trim() == type)) {
    final currency = _currencyLabel(entry.currency);
    result[currency] = (result[currency] ?? 0) + entry.amountMinor;
  }
  return result;
}

String _sourceTotalsText(Map<String, int> totals) => totals.entries
    .where((entry) => entry.value != 0)
    .map((entry) => _money(entry.value, _currencyLabel(entry.key)))
    .join(' + ');

String _currencyLabel(String value) =>
    value.toUpperCase() == 'CNY' || value.toUpperCase() == 'RMB'
    ? 'RMB'
    : value.toUpperCase();
String _documentType(OrderDocumentType value) => switch (value) {
  OrderDocumentType.pi => 'PI',
  OrderDocumentType.ci => 'CI',
  OrderDocumentType.pl => 'PL',
  OrderDocumentType.co => 'CO',
  OrderDocumentType.payment => '收款',
  OrderDocumentType.image => '图片',
  OrderDocumentType.other => '其他',
};
String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _money(int value, String currency) =>
    '$currency ${(value / 100).toStringAsFixed(2)}';
String _quantity(OrderProductionItem item) =>
    '${(item.quantityMilli / 1000).toStringAsFixed(item.quantityMilli % 1000 == 0 ? 0 : 3)} ${item.unit}';
String _fileSize(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
IconData _fileIcon(String name) {
  final extension = name.split('.').last.toLowerCase();
  if (extension == 'pdf') return Icons.picture_as_pdf_outlined;
  if (['png', 'jpg', 'jpeg'].contains(extension)) return Icons.image_outlined;
  if (['xls', 'xlsx'].contains(extension)) return Icons.table_chart_outlined;
  if (['doc', 'docx'].contains(extension)) return Icons.description_outlined;
  return Icons.insert_drive_file_outlined;
}
