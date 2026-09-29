import '../../../l10n/service_error_copy.dart';

import 'package:flutter/material.dart';

import '../../../l10n/crm_copy.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/fly_localizations.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/workspace_empty_state.dart';
import '../../../shared/design_system/destructive_action.dart';
import '../../../shared/design_system/priority.dart';
import '../../../shared/formatters/relative_date_formatter.dart';
import '../../../shared/export/fly_excel_export_action.dart';
import '../../../shared/domain/priority.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_providers.dart';
import '../domain/customer.dart';
import '../domain/customer_name.dart';
import 'customer_duplicate_dialog.dart';
import '../import/customer_import_dialog.dart';
import 'customer_providers.dart';

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
  final _quickAddController = TextEditingController();
  final _searchController = TextEditingController();
  final _quickAddFocus = FocusNode();
  bool _adding = false;
  bool _creating = false;
  final _followUpPending = <String>{};

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
    _quickAddController.dispose();
    _searchController.dispose();
    _quickAddFocus.dispose();
    super.dispose();
  }

  Future<void> _createCustomer() async {
    final name = _quickAddController.text.trim();
    if (name.isEmpty || _creating) return;
    _creating = true;
    try {
      final customer = await ref
          .read(customerRepositoryProvider)
          .createCustomer(
            name: name,
            categoryId: widget.projection == CustomerProjection.category
                ? widget.categoryId
                : null,
          );
      if (!mounted) return;
      _quickAddController.clear();
      ref.read(selectedCustomerIdProvider.notifier).state = customer.id;
      _quickAddFocus.requestFocus();
    } on DuplicateCustomerName catch (e) {
      if (!mounted) return;
      final open = await showCustomerDuplicate(context, e.existing);
      if (!mounted) return;
      if (open) {
        ref.read(selectedCustomerIdProvider.notifier).state = e.existing.id;
        context.go('/customers/all');
      } else {
        _quickAddFocus.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.flyError(e))));
      }
    } finally {
      _creating = false;
    }
  }

  Future<void> _deleteTag(CrmTag tag) async {
    final repository = ref.read(customerRepositoryProvider);
    final references = await repository.tagReferences(tag.id);
    if (!mounted) return;
    if (references.isProtected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.crmCopy('客户级别关联标签请通过“客户级别”管理'))),
      );
      return;
    }
    if (references.noteReferences > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlyLocalizations.of(context).t('tagUsedByNotes')),
        ),
      );
      return;
    }
    final hasReferences = references.hasBusinessReferences;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.l10n.isZh
              ? '删除标签“${tag.name}”？'
              : 'Delete tag “${tag.name}”?',
        ),
        content: hasReferences
            ? Text(
                context.l10n.isZh
                    ? '“${tag.name}”仍被 ${references.customerReferences} 个客户和 '
                          '${references.orderReferences} 个订单使用。\n\n'
                          '删除后，这些客户和订单将移除此标签。是否继续？'
                    : '“${tag.name}” is used by ${references.customerReferences} customers and ${references.orderReferences} orders.\n\nDeleting it removes the tag from those records. Continue?',
              )
            : Text(context.crmCopy('此标签当前没有客户或订单引用。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.crmCopy('取消')),
          ),
          TextButton(
            key: const ValueKey('confirm-delete-tag'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: FlyColors.danger),
            child: Text(context.crmCopy('删除标签')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.deleteTagDefinition(tag.id);
    final selected = {...ref.read(customerTagFilterProvider)}..remove(tag.id);
    ref.read(customerTagFilterProvider.notifier).state = selected;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.crmCopy('标签已删除'))));
  }

  Future<void> _showCustomerDeleteMenu(
    Customer customer,
    int orderCount,
    Offset position,
  ) async {
    final selected = await showFlyDeleteContextMenu(
      context,
      position,
      label: context.crmCopy('删除客户'),
    );
    if (!selected || !mounted) return;
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
    final categories =
        ref.watch(customerCategoriesProvider).valueOrNull ?? const [];
    final statuses =
        ref.watch(customerStatusesProvider).valueOrNull ?? const [];
    final allTags = ref.watch(allCrmTagsProvider).valueOrNull ?? const [];
    final categoryTagIds = categories
        .map((item) => item.tagId)
        .nonNulls
        .toSet();
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
    final selectedTags = ref.watch(customerTagFilterProvider);
    final canCreate = widget.projection != CustomerProjection.deleted;

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
                      _title(categories),
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('import-customers'),
                    tooltip: context.crmCopy('导入 Excel'),
                    onPressed: () => showDialog<void>(
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
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                  ),
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
                              ref.read(customerSearchProvider.notifier).state =
                                  '';
                              setState(() {});
                            },
                          ),
                    suffixIconConstraints: const BoxConstraints(minWidth: 34),
                  ),
                ),
              ),
              if (allTags.isNotEmpty) ...[
                const SizedBox(height: FlySpacing.xs),
                _TagFilters(
                  tags: allTags,
                  selected: selectedTags,
                  onToggle: (id) {
                    final next = {...selectedTags};
                    next.contains(id) ? next.remove(id) : next.add(id);
                    ref.read(customerTagFilterProvider.notifier).state = next;
                  },
                  onClear: () =>
                      ref.read(customerTagFilterProvider.notifier).state = {},
                  onDelete: _deleteTag,
                  protectedTagIds: categoryTagIds,
                ),
              ],
              const SizedBox(height: FlySpacing.xs),
              if (canCreate)
                AnimatedSwitcher(
                  duration: FlyMotion.standard,
                  child: _adding
                      ? TextField(
                          key: const ValueKey('customer-quick-add-input'),
                          controller: _quickAddController,
                          focusNode: _quickAddFocus,
                          autofocus: true,
                          onSubmitted: (_) => _createCustomer(),
                          decoration: InputDecoration(
                            hintText: context.crmCopy('输入客户名称，Enter 创建到收集箱'),
                            prefixIcon: const Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 18,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close, size: 17),
                              onPressed: () => setState(() => _adding = false),
                            ),
                          ),
                        )
                      : Align(
                          key: const ValueKey('customer-quick-add-button'),
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => setState(() => _adding = true),
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(context.crmCopy('添加客户')),
                          ),
                        ),
                ),
              const SizedBox(height: FlySpacing.xs),
              Expanded(
                child: customers.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator.adaptive()),
                  error: (error, stack) => Center(
                    child: Text(
                      context.l10n.isZh
                          ? '客户读取失败：${context.flyError(error)}'
                          : 'Unable to load customers: ${context.flyError(error)}',
                    ),
                  ),
                  data: (items) => items.isEmpty
                      ? widget.projection == CustomerProjection.deleted
                            ? const _EmptyCustomerList()
                            : WorkspaceEmptyState(
                                icon: Icons.people_outline,
                                title: context.crmCopy('这里还没有客户'),
                                actionLabel: context.crmCopy('添加客户'),
                                onCreate: () => setState(() => _adding = true),
                              )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 5),
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
                                widget.projection == CustomerProjection.deleted,
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
                                widget.projection == CustomerProjection.deleted
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
    );
  }
}

class _TagFilters extends StatelessWidget {
  const _TagFilters({
    required this.tags,
    required this.selected,
    required this.onToggle,
    required this.onClear,
    required this.onDelete,
    required this.protectedTagIds,
  });
  final List<CrmTag> tags;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;
  final ValueChanged<CrmTag> onDelete;
  final Set<String> protectedTagIds;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      double widthOf(String label, {bool deletable = false}) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: const TextStyle(fontSize: 12)),
          textDirection: TextDirection.ltr,
        )..layout();
        // Keep a small measurement reserve for the platform font metrics.
        // The visible pills use 16 px horizontal padding; the extra reserve
        // prevents a one-to-three pixel overflow on Windows text rendering.
        return painter.width + 24 + (deletable ? 18 : 0);
      }

      bool fits(int tagCount, {required bool includeMore}) {
        final widths = <double>[
          widthOf(context.crmCopy('全部')),
          ...tags
              .take(tagCount)
              .map((tag) => widthOf(tag.name, deletable: true)),
          if (includeMore) widthOf(context.crmCopy('更多 ›')),
        ];
        var line = 1;
        var used = 0.0;
        for (final width in widths) {
          final next = used == 0 ? width : used + 5 + width;
          if (next <= constraints.maxWidth) {
            used = next;
          } else {
            line++;
            used = width;
          }
          if (line > 2) return false;
        }
        return true;
      }

      var visibleCount = tags.length;
      if (!fits(visibleCount, includeMore: false)) {
        visibleCount = tags.length - 1;
        while (visibleCount > 0 && !fits(visibleCount, includeMore: true)) {
          visibleCount--;
        }
      }
      final visible = tags.take(visibleCount).toList();
      final hasMore = visibleCount < tags.length;
      final entries = <({double width, Widget child})>[
        (
          width: widthOf(context.crmCopy('全部')),
          child: _FilterPill(
            label: context.crmCopy('全部'),
            active: selected.isEmpty,
            onTap: onClear,
          ),
        ),
        for (final tag in visible)
          (
            width: widthOf(tag.name, deletable: true),
            child: _FilterPill(
              label: tag.name,
              color: Color(tag.colorValue),
              active: selected.contains(tag.id),
              onTap: () => onToggle(tag.id),
              onDelete: protectedTagIds.contains(tag.id)
                  ? null
                  : () => onDelete(tag),
              deleteKey: ValueKey('delete-tag-${tag.id}'),
            ),
          ),
        if (hasMore)
          (
            width: widthOf(context.crmCopy('更多 ›')),
            child: _MoreTagFilter(
              tags: tags,
              selected: selected,
              onToggle: onToggle,
            ),
          ),
      ];
      final rows = <List<Widget>>[[]];
      var used = 0.0;
      for (final entry in entries) {
        final next = used == 0 ? entry.width : used + 5 + entry.width;
        if (next > constraints.maxWidth && rows.length == 1) {
          rows.add([]);
          used = 0;
        }
        if (rows.last.isNotEmpty) rows.last.add(const SizedBox(width: 5));
        rows.last.add(entry.child);
        used = used == 0 ? entry.width : used + 5 + entry.width;
      }
      return SizedBox(
        key: const ValueKey('customer-tag-filter-two-lines'),
        height: rows.length == 1 ? 27 : 59,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              Row(children: rows[index]),
              if (index == 0 && rows.length > 1) const SizedBox(height: 5),
            ],
          ],
        ),
      );
    },
  );
}

class _MoreTagFilter extends StatelessWidget {
  const _MoreTagFilter({
    required this.tags,
    required this.selected,
    required this.onToggle,
  });

  final List<CrmTag> tags;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (buttonContext) => Tooltip(
      message: context.crmCopy('更多标签'),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: () async {
          final button = buttonContext.findRenderObject()! as RenderBox;
          final overlay =
              Overlay.of(context).context.findRenderObject()! as RenderBox;
          final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
          final bottomRight = button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay,
          );
          final value = await showMenu<String>(
            context: context,
            position: RelativeRect.fromRect(
              Rect.fromPoints(topLeft, bottomRight),
              Offset.zero & overlay.size,
            ),
            items: [
              for (final tag in tags)
                CheckedPopupMenuItem(
                  value: tag.id,
                  checked: selected.contains(tag.id),
                  child: Text(tag.name),
                ),
            ],
          );
          if (value != null) onToggle(value);
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(context.crmCopy('更多 ›'), style: TextStyle(fontSize: 12)),
        ),
      ),
    ),
  );
}

class _FilterPill extends StatefulWidget {
  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
    this.onDelete,
    this.deleteKey,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? color;
  final VoidCallback? onDelete;
  final Key? deleteKey;

  @override
  State<_FilterPill> createState() => _FilterPillState();
}

class _FilterPillState extends State<_FilterPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: widget.active
              ? (widget.color ?? FlyColors.accentSoft)
              : _hovered
              ? Theme.of(context).hoverColor
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: widget.active
              ? Border.all(color: FlyColors.accent.withValues(alpha: .20))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.label, style: const TextStyle(fontSize: 12)),
            if (widget.onDelete != null) ...[
              const SizedBox(width: 4),
              SizedBox.square(
                dimension: 14,
                child: IgnorePointer(
                  ignoring: !_hovered,
                  child: AnimatedOpacity(
                    duration: FlyMotion.fast,
                    opacity: _hovered ? 1 : 0,
                    child: GestureDetector(
                      key: widget.deleteKey,
                      onTap: widget.onDelete,
                      behavior: HitTestBehavior.opaque,
                      child: const Icon(
                        Icons.close,
                        size: 13,
                        color: FlyColors.danger,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
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
          child: Row(
            children: [
              AnimatedContainer(
                duration: FlyMotion.fast,
                width: 2,
                height: selected ? 30 : 0,
                decoration: BoxDecoration(
                  color: selected ? FlyColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              if (deletedView)
                IconButton(
                  tooltip: context.crmCopy('恢复客户'),
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore, size: 19),
                )
              else
                Checkbox(
                  value: followed,
                  onChanged: (_) => onComplete(),
                  visualDensity: VisualDensity.compact,
                ),
              Expanded(
                flex: 4,
                child: Text(
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
              ),
              Expanded(
                flex: 3,
                child: Text(
                  customer.country.isEmpty ? '—' : customer.country,
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
              SizedBox(
                width: 54,
                child: Text(
                  RelativeDateFormatter.lastFollowUp(
                    customer.lastFollowUpAt,
                    isZh: context.l10n.isZh,
                  ),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(width: 6),
              Column(
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
                        style: TextStyle(
                          fontSize: 10.5,
                          color: _nextActionColor(customer.nextActionType!),
                        ),
                      ),
                    ),
                  if (customer.nextActionType != null)
                    const SizedBox(height: 3),
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
              const SizedBox(width: 8),
            ],
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
        const SizedBox(height: 4),
        Text(
          context.crmCopy('快速创建后，再在右侧逐步完善信息'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
