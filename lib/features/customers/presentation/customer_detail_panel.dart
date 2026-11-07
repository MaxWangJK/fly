import '../../../l10n/service_error_copy.dart';
import '../../../l10n/fly_localizations.dart';

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../l10n/crm_copy.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/model_text_field.dart';
import '../../../shared/design_system/detail_section_entry.dart';
import '../../../shared/design_system/priority.dart';
import '../../../shared/design_system/tag_container.dart';
import '../../../shared/domain/priority.dart';
import '../../../shared/formatters/relative_date_formatter.dart';
import '../../../shared/attachments/attachment.dart';
import '../../../shared/attachments/attachment_providers.dart';
import '../../orders/domain/order.dart';
import '../../orders/presentation/order_create_dialog.dart';
import '../../orders/presentation/order_providers.dart';
import '../domain/customer.dart';
import '../domain/customer_name.dart';
import 'customer_duplicate_dialog.dart';
import 'customer_providers.dart';
import '../../../app/shell/mobile_details.dart';
import '../../../shared/design_system/responsive_layout.dart';

class CustomerDetailPanel extends ConsumerStatefulWidget {
  const CustomerDetailPanel({required this.customerId, super.key});
  final String customerId;

  @override
  ConsumerState<CustomerDetailPanel> createState() =>
      _CustomerDetailPanelState();
}

class _CustomerDetailPanelState extends ConsumerState<CustomerDetailPanel> {
  List<Customer> _duplicates = const [];

  Future<void> _save(Customer customer) async {
    try {
      await ref.read(customerRepositoryProvider).saveCustomer(customer);
    } on DuplicateCustomerName catch (e) {
      if (!mounted) return;
      final open = await showCustomerDuplicate(context, e.existing);
      if (open && mounted) {
        ref.read(selectedCustomerIdProvider.notifier).state = e.existing.id;
        context.go('/customers/all');
      }
    }
  }

  Future<void> _checkDuplicates(Customer customer) async {
    final values = await ref
        .read(customerRepositoryProvider)
        .findPotentialDuplicates(
          email: customer.email,
          whatsapp: customer.whatsapp,
          phone: customer.phone,
          excludingCustomerId: customer.id,
        );
    if (mounted) setState(() => _duplicates = values);
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(customerProvider(widget.customerId));
    return value.when(
      skipLoadingOnReload: true,
      loading: () => Center(child: CircularProgressIndicator.adaptive()),
      error: (error, stack) => Center(
        child: Text(
          (context.l10n.isZh
              ? '客户详情读取失败：${context.flyError(error)}'
              : 'Unable to load customer details: ${context.flyError(error)}'),
        ),
      ),
      data: (customer) {
        if (customer == null) {
          return Center(child: Text(context.crmCopy('客户不存在')));
        }
        final categories =
            ref.watch(customerCategoriesProvider).valueOrNull ?? const [];
        final statuses =
            ref.watch(customerStatusesProvider).valueOrNull ?? const [];
        final sources =
            ref.watch(allCustomerSourcesProvider).valueOrNull ?? const [];
        final tags =
            ref.watch(customerTagsProvider(customer.id)).valueOrNull ??
            const [];
        final allTags = ref.watch(allCrmTagsProvider).valueOrNull ?? const [];
        final contacts =
            ref.watch(customerContactsProvider(customer.id)).valueOrNull ??
            const [];
        final customDefinitions =
            ref.watch(customerCustomFieldDefinitionsProvider).valueOrNull ??
            const [];
        final customValues =
            ref
                .watch(customerCustomFieldValuesProvider(customer.id))
                .valueOrNull ??
            const [];
        final latestNote = ref
            .watch(latestCustomerNoteProvider(customer.id))
            .valueOrNull;
        final latestFollowUp = ref
            .watch(latestCustomerFollowUpProvider(customer.id))
            .valueOrNull;
        final latestNextAction = ref
            .watch(latestCustomerNextActionProvider(customer.id))
            .valueOrNull;
        final orders =
            ref.watch(customerOrdersProvider(customer.id)).valueOrNull ??
            const [];
        final attachments =
            ref
                .watch(
                  ownerAttachmentsProvider((
                    ownerType: AttachmentOwnerType.customer,
                    ownerId: customer.id,
                  )),
                )
                .valueOrNull ??
            const <FlyAttachment>[];

        return Material(
          key: ValueKey('customer-details-${customer.id}'),
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 420;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
                  children: [
                    _CustomerHeader(
                      customer: customer,
                      hasOrders: orders.isNotEmpty,
                      onSave: _save,
                    ),
                    if (latestNextAction != null) ...[
                      const SizedBox(height: FlySpacing.xs),
                      _NextAction(value: latestNextAction),
                    ],
                    if (_duplicates.isNotEmpty) ...[
                      const SizedBox(height: FlySpacing.xs),
                      _DuplicateWarning(customers: _duplicates),
                    ],
                    const SizedBox(height: FlySpacing.sm),
                    _ResponsiveFieldGrid(
                      twoColumns: twoColumns,
                      children: [
                        _SelectField<String>(
                          icon: Icons.grade_outlined,
                          label: context.crmCopy('客户级别'),
                          value: customer.categoryId,
                          items: [
                            for (final item in categories)
                              DropdownMenuItem(
                                value: item.id,
                                child: Text(item.name),
                              ),
                          ],
                          onChanged: (value) =>
                              _save(customer.copyWith(categoryId: value)),
                        ),
                        _SelectField<String>(
                          icon: Icons.track_changes_outlined,
                          label: context.crmCopy('客户状态'),
                          value: customer.statusId,
                          items: [
                            for (final item in statuses)
                              DropdownMenuItem(
                                value: item.id,
                                child: Text(item.name),
                              ),
                          ],
                          onChanged: (value) =>
                              _save(customer.copyWith(statusId: value)),
                        ),
                        _CustomsInformationField(
                          value: customer.customsInfo,
                          onSave: (value) =>
                              _save(customer.copyWith(customsInfo: value)),
                        ),
                        _PriorityField(
                          value: customer.priority,
                          onChanged: (value) =>
                              _save(customer.copyWith(priority: value)),
                        ),
                        _DateField(customer: customer, onSave: _save),
                        _RecurrenceField(
                          value: customer.followUpRecurrence,
                          onChanged: (value) {
                            final nextDate =
                                customer.nextFollowUpDate == null &&
                                    value != FollowUpRecurrence.never
                                ? nextCustomerFollowUpDate(
                                    recurrence: value,
                                    now: DateTime.now(),
                                  )
                                : customer.nextFollowUpDate;
                            _save(
                              customer.copyWith(
                                followUpRecurrence: value,
                                nextFollowUpDate: nextDate,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: FlySpacing.md),
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
                          .read(customerRepositoryProvider)
                          .setCustomerTags(customer.id, ids),
                      onCreate: (name) async {
                        final tag = await ref
                            .read(customerRepositoryProvider)
                            .findOrCreateTag(name);
                        return FlyTagItem(
                          id: tag.id,
                          name: tag.name,
                          colorValue: tag.colorValue,
                        );
                      },
                    ),
                    const SizedBox(height: FlySpacing.md),
                    DetailSectionEntry(
                      key: const ValueKey('customer-notes-preview'),
                      title: context.crmCopy('备注'),
                      icon: Icons.sticky_note_2_outlined,
                      preview: Text(
                        latestNote?.content ??
                            context.crmCopy('记录客户偏好、谈判信息和长期观察'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                      meta: latestNote == null
                          ? context.crmCopy('点击开始记录')
                          : RelativeDateFormatter.dateTime(
                              latestNote.createdAt,
                              isZh: context.l10n.isZh,
                            ),
                      onTap: () =>
                          ref
                              .read(customerDetailExtensionProvider.notifier)
                              .state = DetailExtensionType
                              .notes,
                    ),
                    const SizedBox(height: FlySpacing.sm),
                    DetailSectionEntry(
                      key: const ValueKey('customer-followup-preview'),
                      title: context.crmCopy('跟进记录'),
                      icon: Icons.forum_outlined,
                      preview: Text(
                        latestFollowUp == null
                            ? context.crmCopy('记录刚刚发生的客户沟通')
                            : latestFollowUp.content.isNotEmpty
                            ? latestFollowUp.content
                            : (context.l10n.isZh
                                  ? '下一步：${latestFollowUp.nextAction}'
                                  : 'Next action: ${latestFollowUp.nextAction}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                      meta: latestFollowUp == null
                          ? context.crmCopy('点击开始记录')
                          : '${latestFollowUp.channel} · ${RelativeDateFormatter.dateTime(latestFollowUp.followedUpAt, isZh: context.l10n.isZh)}',
                      onTap: () =>
                          ref
                              .read(customerDetailExtensionProvider.notifier)
                              .state = DetailExtensionType
                              .followUps,
                    ),
                    const SizedBox(height: FlySpacing.md),
                    _OrdersSummary(customer: customer, orders: orders),
                    const SizedBox(height: FlySpacing.sm),
                    _CustomerAttachmentsSection(
                      customer: customer,
                      attachments: attachments,
                    ),
                    const SizedBox(height: FlySpacing.sm),
                    ExpansionTile(
                      initiallyExpanded: true,
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(
                        bottom: FlySpacing.md,
                      ),
                      title: Text(
                        context.crmCopy('基本信息'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      children: [
                        _BasicInformation(
                          customer: customer,
                          contacts: contacts,
                          customDefinitions: customDefinitions,
                          customValues: customValues,
                          sources: sources,
                          onSave: _save,
                          onCheckDuplicates: _checkDuplicates,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _CustomerAttachmentsSection extends ConsumerStatefulWidget {
  const _CustomerAttachmentsSection({
    required this.customer,
    required this.attachments,
  });

  final Customer customer;
  final List<FlyAttachment> attachments;

  @override
  ConsumerState<_CustomerAttachmentsSection> createState() =>
      _CustomerAttachmentsSectionState();
}

class _CustomerAttachmentsSectionState
    extends ConsumerState<_CustomerAttachmentsSection> {
  bool _dragging = false;

  Future<void> _pick() async {
    final group = XTypeGroup(
      label: context.crmCopy('客户附件'),
      extensions: ['pdf', 'png', 'jpg', 'jpeg', 'xlsx', 'xls', 'docx', 'doc'],
    );
    final files = await openFiles(acceptedTypeGroups: [group]);
    for (final file in files) {
      await _import(file.path);
    }
  }

  Future<void> _import(String path) async {
    final stored = await ref
        .read(attachmentStorageProvider)
        .importFile(
          ownerType: AttachmentOwnerType.customer,
          ownerId: widget.customer.id,
          sourcePath: path,
        );
    await ref
        .read(attachmentRepositoryProvider)
        .addMetadata(
          id: stored.id,
          ownerType: AttachmentOwnerType.customer,
          ownerId: widget.customer.id,
          fileName: stored.fileName,
          originalName: stored.originalName,
          relativePath: stored.relativePath,
          mimeType: stored.mimeType,
          fileSize: stored.fileSize,
          documentType: _customerDocumentType(stored.originalName),
        );
  }

  Future<void> _remove(FlyAttachment attachment) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.crmCopy('删除附件？')),
            content: Text(
              (context.l10n.isZh
                  ? '将删除 ${attachment.originalName} 的记录和本地文件。'
                  : 'The record and local file for ${attachment.originalName} will be deleted.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.crmCopy('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.crmCopy('删除')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await ref.read(attachmentStorageProvider).delete(attachment.relativePath);
    await ref.read(attachmentRepositoryProvider).removeMetadata(attachment.id);
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragEntered: (_) => setState(() => _dragging = true),
    onDragExited: (_) => setState(() => _dragging = false),
    onDragDone: (detail) async {
      setState(() => _dragging = false);
      for (final file in detail.files) {
        await _import(file.path);
      }
    },
    child: Container(
      key: const ValueKey('customer-attachments'),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _dragging
            ? FlyColors.accent.withValues(alpha: .08)
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(FlyRadius.md),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.attach_file_rounded, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.crmCopy('附件'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('add-customer-attachment'),
                onPressed: _pick,
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: Text(context.crmCopy('上传')),
              ),
            ],
          ),
          if (widget.attachments.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _dragging
                    ? context.crmCopy('松开即可添加')
                    : context.crmCopy('拖入样品、报价、名片、聊天截图或 PDF'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final attachment in widget.attachments)
              ListTile(
                dense: true,
                minTileHeight: 38,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined, size: 17),
                title: Text(
                  attachment.originalName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: Text(
                  '${attachment.documentType} · ${(attachment.fileSize / 1024).toStringAsFixed(0)} KB',
                  style: const TextStyle(fontSize: 10.5),
                ),
                onTap: () => ref
                    .read(attachmentOpenerProvider)
                    .open(
                      ref
                          .read(attachmentStorageProvider)
                          .absolutePath(attachment.relativePath),
                    ),
                trailing: PopupMenuButton<String>(
                  tooltip: context.crmCopy('附件操作'),
                  onSelected: (value) async {
                    if (value == 'delete') {
                      await _remove(attachment);
                    } else {
                      await ref
                          .read(attachmentRepositoryProvider)
                          .changeDocumentType(attachment.id, value);
                    }
                  },
                  itemBuilder: (context) => [
                    for (final value in const [
                      '样品',
                      '报价',
                      '名片',
                      '聊天截图',
                      '合同',
                      '图片',
                      'PDF',
                      '其它',
                    ])
                      PopupMenuItem(
                        value: value,
                        child: Text(context.crmCopy(value)),
                      ),
                    const PopupMenuDivider(),
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
  );
}

String _customerDocumentType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return 'PDF';
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg')) {
    return '图片';
  }
  return '其它';
}

class _CustomerHeader extends ConsumerWidget {
  const _CustomerHeader({
    required this.customer,
    required this.hasOrders,
    required this.onSave,
  });
  final Customer customer;
  final bool hasOrders;
  final Future<void> Function(Customer) onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: [
      Expanded(
        child: _AutoSaveField(
          key: ValueKey('customer-name-${customer.id}'),
          value: customer.name,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            hintText: context.crmCopy('客户名称'),
          ),
          onSave: (value) => onSave(customer.copyWith(name: value)),
        ),
      ),
      PopupMenuButton<String>(
        tooltip: context.crmCopy('更多'),
        onSelected: (value) async {
          if (value != 'delete') return;
          final confirmed = await _confirmDelete(context, hasOrders);
          if (!confirmed || !context.mounted) return;
          await ref
              .read(customerRepositoryProvider)
              .softDeleteCustomer(customer.id);
          ref.read(selectedCustomerIdProvider.notifier).state = null;
          ref.read(customerDetailExtensionProvider.notifier).state =
              DetailExtensionType.none;
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'delete', child: Text(context.crmCopy('移到已删除'))),
        ],
      ),
    ],
  );
}

class _NextAction extends StatelessWidget {
  const _NextAction({required this.value});
  final CustomerFollowUp value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: FlyColors.accentSoft,
      borderRadius: BorderRadius.circular(FlyRadius.sm),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.arrow_forward_rounded,
          size: 16,
          color: FlyColors.accent,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            '下一步：${[if (value.nextActionType != null) value.nextActionType!.label, if (value.nextAction.isNotEmpty) value.nextAction].join(' · ')}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _DuplicateWarning extends StatelessWidget {
  const _DuplicateWarning({required this.customers});
  final List<Customer> customers;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: FlyColors.calendarYellow,
      borderRadius: BorderRadius.circular(FlyRadius.sm),
    ),
    child: Text(
      context.l10n.isZh
          ? '可能已存在该客户：${customers.map((item) => item.name).join('、')}（仍可继续保存）'
          : 'Possible existing customers: ${customers.map((item) => item.name).join(', ')}. You can still save.',
      style: const TextStyle(fontSize: 12, color: FlyColors.warning),
    ),
  );
}

class _ResponsiveFieldGrid extends StatelessWidget {
  const _ResponsiveFieldGrid({
    required this.twoColumns,
    required this.children,
  });
  final bool twoColumns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = twoColumns
          ? (constraints.maxWidth - 8) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _FieldSurface extends StatelessWidget {
  const _FieldSurface({
    required this.icon,
    required this.label,
    required this.child,
  });
  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 62),
    padding: const EdgeInsets.fromLTRB(9, 7, 8, 7),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(FlyRadius.sm),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 5),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        const SizedBox(height: 4),
        child,
      ],
    ),
  );
}

class _SelectField<T> extends StatelessWidget {
  const _SelectField({
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => _FieldSurface(
    icon: icon,
    label: label,
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        isExpanded: true,
        hint: Text(context.crmCopy('未设置'), style: TextStyle(fontSize: 12)),
        style: Theme.of(context).textTheme.bodySmall,
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
}

class _CustomsInformationField extends StatelessWidget {
  const _CustomsInformationField({required this.value, required this.onSave});

  final String value;
  final Future<void> Function(String value) onSave;

  @override
  Widget build(BuildContext context) {
    final firstLine = value.trim().isEmpty
        ? context.crmCopy('点击记录收货人、地址、电话、邮箱')
        : value.trim().split(RegExp(r'\r?\n')).first;
    return _FieldSurface(
      icon: Icons.inventory_2_outlined,
      label: context.crmCopy('报关信息'),
      child: InkWell(
        key: const ValueKey('customer-customs-info'),
        onTap: () async {
          final result = await showDialog<String>(
            context: context,
            builder: (_) => _CustomsInformationDialog(initialValue: value),
          );
          if (result != null) await onSave(result.trim());
        },
        borderRadius: BorderRadius.circular(FlyRadius.xs),
        child: SizedBox(
          height: 24,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              firstLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: value.trim().isEmpty
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomsInformationDialog extends StatefulWidget {
  const _CustomsInformationDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_CustomsInformationDialog> createState() =>
      _CustomsInformationDialogState();
}

class _CustomsInformationDialogState extends State<_CustomsInformationDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.crmCopy('报关信息')),
    content: SizedBox(
      width: 520,
      child: TextField(
        key: const ValueKey('customer-customs-info-input'),
        controller: _controller,
        autofocus: true,
        minLines: 8,
        maxLines: 14,
        style: const TextStyle(fontSize: 14, height: 1.5),
        decoration: InputDecoration(
          alignLabelWithHint: true,
          hintText: context.crmCopy('收货人\n地址\n电话\n邮箱\n其他报关备注…'),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.crmCopy('取消')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(context.crmCopy('保存')),
      ),
    ],
  );
}

class _PriorityField extends StatelessWidget {
  const _PriorityField({required this.value, required this.onChanged});
  final PriorityLevel value;
  final ValueChanged<PriorityLevel> onChanged;

  @override
  Widget build(BuildContext context) => _FieldSurface(
    icon: Icons.flag_outlined,
    label: context.crmCopy('优先级'),
    child: PrioritySelector(value: value, onChanged: onChanged, compact: true),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({required this.customer, required this.onSave});
  final Customer customer;
  final Future<void> Function(Customer) onSave;

  @override
  Widget build(BuildContext context) => _FieldSurface(
    icon: Icons.event_outlined,
    label: context.crmCopy('下次跟进'),
    child: InkWell(
      key: const ValueKey('customer-next-follow-up'),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
          initialDate: customer.nextFollowUpDate ?? DateTime.now(),
        );
        if (date != null) {
          await onSave(customer.copyWith(nextFollowUpDate: date));
        }
      },
      child: Row(
        children: [
          Expanded(
            child: Text(
              customer.nextFollowUpDate == null
                  ? context.crmCopy('未设置')
                  : _dateText(customer.nextFollowUpDate!),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (customer.nextFollowUpDate != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: context.crmCopy('清除'),
              child: InkWell(
                borderRadius: BorderRadius.circular(FlyRadius.xs),
                onTap: () => onSave(customer.copyWith(nextFollowUpDate: null)),
                child: const SizedBox.square(
                  dimension: 20,
                  child: Icon(Icons.close, size: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _RecurrenceField extends StatelessWidget {
  const _RecurrenceField({required this.value, required this.onChanged});
  final FollowUpRecurrence value;
  final ValueChanged<FollowUpRecurrence> onChanged;

  @override
  Widget build(BuildContext context) => _FieldSurface(
    icon: Icons.repeat,
    label: context.crmCopy('重复'),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<FollowUpRecurrence>(
        key: const ValueKey('customer-recurrence'),
        value: value,
        isDense: true,
        isExpanded: true,
        style: Theme.of(context).textTheme.bodySmall,
        items: [
          for (final recurrence in FollowUpRecurrence.values)
            DropdownMenuItem(
              value: recurrence,
              child: Text(context.crmCopy(_recurrenceName(recurrence))),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    ),
  );
}

class _OrdersSummary extends ConsumerWidget {
  const _OrdersSummary({required this.customer, required this.orders});
  final Customer customer;
  final List<SalesOrder> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = orders.fold(0, (sum, item) => sum + item.salesAmount);
    final latest = orders.isEmpty
        ? null
        : orders.reduce(
            (left, right) =>
                left.createdAt.isAfter(right.createdAt) ? left : right,
          );
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(FlyRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.crmCopy('订单'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                key: const ValueKey('view-customer-orders'),
                onPressed: () {
                  ref.read(orderCustomerFilterProvider.notifier).state =
                      customer.id;
                  ref.read(selectedOrderIdProvider.notifier).state = null;
                  ref.read(orderExtensionProvider.notifier).state =
                      OrderExtensionType.none;
                  ref.read(customerDetailExtensionProvider.notifier).state =
                      DetailExtensionType.none;
                  if (useCompactLayout(context)) Navigator.pop(context);
                  context.go('/orders/all');
                },
                child: Text(context.crmCopy('查看订单')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('create-order-for-customer'),
                onPressed: () async {
                  final order = await showDialog<SalesOrder>(
                    context: context,
                    builder: (_) => OrderCreateDialog(
                      customerId: customer.id,
                      customerName: customer.name,
                    ),
                  );
                  if (order == null || !context.mounted) return;
                  ref.read(orderCustomerFilterProvider.notifier).state =
                      customer.id;
                  ref.read(orderSearchProvider.notifier).state = '';
                  ref.read(selectedOrderIdProvider.notifier).state = order.id;
                  ref.read(orderExtensionProvider.notifier).state =
                      OrderExtensionType.none;
                  ref.read(customerDetailExtensionProvider.notifier).state =
                      DetailExtensionType.none;
                  if (context.mounted) {
                    if (useCompactLayout(context)) {
                      final navigator = Navigator.of(context);
                      final router = GoRouter.of(context);
                      navigator.pop();
                      router.go('/orders/all');
                      final sheetContext = navigator.context;
                      if (sheetContext.mounted) {
                        await showOrderDetailSheet(sheetContext, order.id);
                      }
                    } else {
                      context.go('/orders/all');
                    }
                  }
                },
                icon: const Icon(Icons.add, size: 15),
                label: Text(context.crmCopy('新建订单')),
              ),
            ],
          ),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                (context.l10n.isZh
                    ? '订单 ${orders.length}'
                    : 'Orders ${orders.length}'),
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                '${context.crmCopy('总金额')} ${_money(total, orders.firstOrNull?.currency ?? 'USD')}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                '${context.crmCopy('最近')} ${latest == null ? '—' : _dateText(latest.orderDate ?? latest.createdAt)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BasicInformation extends ConsumerWidget {
  const _BasicInformation({
    required this.customer,
    required this.contacts,
    required this.customDefinitions,
    required this.customValues,
    required this.sources,
    required this.onSave,
    required this.onCheckDuplicates,
  });
  final Customer customer;
  final List<CustomerContact> contacts;
  final List<CustomerCustomFieldDefinition> customDefinitions;
  final List<CustomerCustomFieldValue> customValues;
  final List<CustomerSource> sources;
  final Future<void> Function(Customer) onSave;
  final Future<void> Function(Customer) onCheckDuplicates;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      _FieldGrid(
        children: [
          _CustomerTextField(
            label: context.crmCopy('公司名称'),
            value: customer.companyName,
            onSave: (value) => onSave(customer.copyWith(companyName: value)),
          ),
          _CustomerTextField(
            label: context.crmCopy('国家'),
            value: customer.country,
            onSave: (value) => onSave(customer.copyWith(country: value)),
          ),
          _CustomerTextField(
            label: context.crmCopy('城市'),
            value: customer.city,
            onSave: (value) => onSave(customer.copyWith(city: value)),
          ),
          _CustomerTextField(
            label: context.crmCopy('客户来源'),
            value:
                sources
                    .where((s) => s.id == customer.sourceId)
                    .firstOrNull
                    ?.name ??
                '',
            onSave: (value) => ref
                .read(customerRepositoryProvider)
                .setCustomerSourceText(customer.id, value),
          ),
          _CustomerTextField(
            label: context.crmCopy('地址'),
            value: customer.address,
            onSave: (value) => onSave(customer.copyWith(address: value)),
          ),
          _CustomerTextField(
            label: 'Website',
            value: customer.website,
            onSave: (value) => onSave(customer.copyWith(website: value)),
          ),
          _CustomerTextField(
            label: 'WhatsApp',
            value: customer.whatsapp,
            onSave: (value) async {
              final next = customer.copyWith(whatsapp: value);
              await onSave(next);
              await onCheckDuplicates(next);
            },
          ),
          _CustomerTextField(
            label: 'Email',
            value: customer.email,
            onSave: (value) async {
              final next = customer.copyWith(email: value);
              await onSave(next);
              await onCheckDuplicates(next);
            },
          ),
          _CustomerTextField(
            label: 'Phone',
            value: customer.phone,
            onSave: (value) async {
              final next = customer.copyWith(phone: value);
              await onSave(next);
              await onCheckDuplicates(next);
            },
          ),
          _CustomerTextField(
            label: 'Facebook',
            value: customer.facebook,
            onSave: (value) => onSave(customer.copyWith(facebook: value)),
          ),
          _CustomerTextField(
            label: 'LinkedIn',
            value: customer.linkedIn,
            onSave: (value) => onSave(customer.copyWith(linkedIn: value)),
          ),
          _CustomerTextField(
            label: 'Alibaba',
            value: customer.alibaba,
            onSave: (value) => onSave(customer.copyWith(alibaba: value)),
          ),
          _CustomerTextField(
            label: 'Instagram',
            value: customer.instagram,
            onSave: (value) => onSave(customer.copyWith(instagram: value)),
          ),
          _CustomerTextField(
            label: 'WeChat',
            value: customer.wechat,
            onSave: (value) => onSave(customer.copyWith(wechat: value)),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              context.crmCopy('自定义字段'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton.icon(
            key: const ValueKey('add-customer-custom-field'),
            onPressed: () => _addCustomField(context, ref),
            icon: const Icon(Icons.add, size: 16),
            label: Text(context.crmCopy('添加字段')),
          ),
        ],
      ),
      if (customDefinitions.isEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            context.crmCopy('添加后会在所有客户中使用同一字段定义。'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        )
      else
        _FieldGrid(
          children: [
            for (final definition in customDefinitions)
              _CustomFieldEditor(
                customerId: customer.id,
                definition: definition,
                value:
                    customValues
                        .where((value) => value.definitionId == definition.id)
                        .firstOrNull
                        ?.value ??
                    '',
              ),
          ],
        ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              context.crmCopy('联系人'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton.icon(
            onPressed: () => _addContact(context, ref, customer.id),
            icon: const Icon(Icons.add, size: 16),
            label: Text(context.crmCopy('添加')),
          ),
        ],
      ),
      for (final contact in contacts)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            contact.isPrimary ? Icons.star_rounded : Icons.person_outline,
            size: 18,
            color: contact.isPrimary ? FlyColors.warning : null,
          ),
          title: Text(
            '${contact.name}${contact.role.isEmpty ? '' : ' · ${contact.role}'}',
          ),
          subtitle: Text(
            [
              contact.email,
              contact.phone,
              contact.whatsapp,
            ].where((value) => value.isNotEmpty).join('  ·  '),
          ),
          trailing: IconButton(
            tooltip: context.crmCopy('删除联系人'),
            onPressed: () =>
                ref.read(customerRepositoryProvider).removeContact(contact.id),
            icon: const Icon(Icons.close, size: 17),
          ),
        ),
    ],
  );
}

class _AutoSaveField extends StatefulWidget {
  const _AutoSaveField({
    required this.value,
    required this.onSave,
    required this.decoration,
    this.style,
    this.keyboardType,
    super.key,
  });
  final String value;
  final ValueChanged<String> onSave;
  final InputDecoration decoration;
  final TextStyle? style;
  final TextInputType? keyboardType;

  @override
  State<_AutoSaveField> createState() => _AutoSaveFieldState();
}

class _AutoSaveFieldState extends State<_AutoSaveField> {
  late final TextEditingController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _AutoSaveField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        _controller.text == oldWidget.value) {
      _controller.syncTextFromModel(widget.value);
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
    keyboardType: widget.keyboardType,
    decoration: widget.decoration,
    onChanged: (value) {
      _timer?.cancel();
      _timer = Timer(FlyMotion.autoSave, () => widget.onSave(value.trim()));
    },
  );
}

class _CustomerTextField extends StatelessWidget {
  const _CustomerTextField({
    required this.label,
    required this.value,
    required this.onSave,
  });
  final String label;
  final String value;
  final ValueChanged<String> onSave;

  @override
  Widget build(BuildContext context) => _AutoSaveField(
    key: ValueKey('customer-text-$label'),
    value: value,
    onSave: onSave,
    decoration: InputDecoration(isDense: true, labelText: label),
  );
}

class _CustomFieldEditor extends ConsumerWidget {
  const _CustomFieldEditor({
    required this.customerId,
    required this.definition,
    required this.value,
  });

  final String customerId;
  final CustomerCustomFieldDefinition definition;
  final String value;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _AutoSaveField(
    key: ValueKey('custom-field-$customerId-${definition.id}'),
    value: value,
    keyboardType: definition.type == CustomerCustomFieldType.number
        ? const TextInputType.numberWithOptions(decimal: true)
        : definition.type == CustomerCustomFieldType.date
        ? TextInputType.datetime
        : TextInputType.text,
    onSave: (next) => ref
        .read(customerRepositoryProvider)
        .setCustomFieldValue(customerId, definition.id, next),
    decoration: InputDecoration(
      isDense: true,
      labelText: definition.name,
      hintText: definition.type == CustomerCustomFieldType.date
          ? 'YYYY-MM-DD'
          : null,
      suffixIcon: PopupMenuButton<String>(
        tooltip: context.crmCopy('字段设置'),
        onSelected: (action) async {
          if (action != 'delete') return;
          final repository = ref.read(customerRepositoryProvider);
          final count = await repository.customFieldValueCount(definition.id);
          if (!context.mounted) return;
          final confirmed =
              await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(
                    (context.l10n.isZh
                        ? '删除“${definition.name}”？'
                        : 'Delete “${definition.name}”?'),
                  ),
                  content: Text(
                    (context.l10n.isZh
                        ? '会删除 $count 个客户中的该字段值，此操作不会删除客户。'
                        : 'This removes the field values from $count customers. The customers will be retained.'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(context.crmCopy('取消')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(context.crmCopy('删除字段')),
                    ),
                  ],
                ),
              ) ??
              false;
          if (confirmed) {
            await repository.deleteCustomFieldDefinition(definition.id);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'delete', child: Text(context.crmCopy('删除字段'))),
        ],
        icon: const Icon(Icons.more_horiz, size: 16),
      ),
    ),
  );
}

class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 420;
      final width = columns
          ? (constraints.maxWidth - 8) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

Future<bool> _confirmDelete(BuildContext context, bool hasOrders) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.crmCopy('删除客户？')),
        content: Text(
          hasOrders
              ? context.crmCopy('该客户有关联订单。客户会进入“已删除”，订单会保留。')
              : context.crmCopy('客户会进入“已删除”，可随时恢复。'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.crmCopy('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.crmCopy('移到已删除')),
          ),
        ],
      ),
    ) ??
    false;

Future<void> _addCustomField(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  var type = CustomerCustomFieldType.text;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.crmCopy('添加自定义字段')),
        content: SizedBox(
          width: 340,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('custom-field-name-input'),
                  controller: name,
                  autofocus: true,
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: context.crmCopy('字段名称'),
                    hintText: context.crmCopy('例如：年采购量'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<CustomerCustomFieldType>(
                  initialValue: type,
                  isDense: true,
                  decoration: InputDecoration(labelText: context.crmCopy('类型')),
                  items: [
                    DropdownMenuItem(
                      value: CustomerCustomFieldType.text,
                      child: Text(context.crmCopy('文本')),
                    ),
                    DropdownMenuItem(
                      value: CustomerCustomFieldType.number,
                      child: Text(context.crmCopy('数字')),
                    ),
                    DropdownMenuItem(
                      value: CustomerCustomFieldType.date,
                      child: Text(context.crmCopy('日期')),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => type = value ?? CustomerCustomFieldType.text,
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
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.crmCopy('添加')),
          ),
        ],
      ),
    ),
  );
  if (result == true && name.text.trim().isNotEmpty) {
    await ref
        .read(customerRepositoryProvider)
        .createCustomFieldDefinition(name.text, type: type);
  }
  name.dispose();
}

Future<void> _addContact(
  BuildContext context,
  WidgetRef ref,
  String customerId,
) async {
  final name = TextEditingController();
  final role = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final whatsapp = TextEditingController();
  var primary = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.crmCopy('添加联系人')),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(labelText: context.crmCopy('姓名 *')),
              ),
              TextField(
                controller: role,
                decoration: InputDecoration(labelText: context.crmCopy('职位')),
              ),
              TextField(
                controller: email,
                decoration: InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: phone,
                decoration: InputDecoration(labelText: 'Phone'),
              ),
              TextField(
                controller: whatsapp,
                decoration: InputDecoration(labelText: 'WhatsApp'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.crmCopy('主要联系人')),
                value: primary,
                onChanged: (value) =>
                    setDialogState(() => primary = value ?? false),
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
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.crmCopy('添加')),
          ),
        ],
      ),
    ),
  );
  if (result == true && name.text.trim().isNotEmpty) {
    await ref
        .read(customerRepositoryProvider)
        .addContact(
          customerId,
          name: name.text.trim(),
          role: role.text.trim(),
          email: email.text.trim(),
          phone: phone.text.trim(),
          whatsapp: whatsapp.text.trim(),
          isPrimary: primary,
        );
  }
  for (final controller in [name, role, email, phone, whatsapp]) {
    controller.dispose();
  }
}

String _recurrenceName(FollowUpRecurrence value) => switch (value) {
  FollowUpRecurrence.never => '从不',
  FollowUpRecurrence.every3Days => '三天',
  FollowUpRecurrence.weekly => '每周',
  FollowUpRecurrence.biweekly => '两周',
  FollowUpRecurrence.monthly => '每月',
  FollowUpRecurrence.every2Months => '两月',
};
String _dateText(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _money(int minorUnits, String currency) =>
    '$currency ${(minorUnits / 100).toStringAsFixed(2)}';
