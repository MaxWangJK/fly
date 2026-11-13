import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../l10n/service_error_copy.dart';
import '../../../shared/design_system/responsive_layout.dart';
import '../data/drift_customer_repository.dart';
import '../domain/customer.dart';
import '../domain/customer_lifecycle.dart';
import 'customer_providers.dart';

class CustomerStatusChoices extends ConsumerStatefulWidget {
  const CustomerStatusChoices({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  @override
  ConsumerState<CustomerStatusChoices> createState() =>
      _CustomerStatusChoicesState();
}

class _CustomerStatusChoicesState extends ConsumerState<CustomerStatusChoices> {
  bool working = false;
  String? error;
  String t(String zh, String en) => context.l10n.isZh ? zh : en;

  Future<void> edit([CustomerStatus? item]) async {
    if (isMobilePlatform || working || !widget.enabled) return;
    FocusScope.of(context).unfocus();
    setState(() {
      working = true;
      error = null;
    });
    try {
      final id = await showDialog<String>(
        context: context,
        builder: (_) => _StatusNameDialog(item: item),
      );
      if (mounted && id != null && item == null) widget.onChanged(id);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> remove(CustomerStatus item) async {
    if (isMobilePlatform || working || !widget.enabled) return;
    FocusScope.of(context).unfocus();
    setState(() {
      working = true;
      error = null;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(t('删除客户状态？', 'Delete customer status?')),
          content: Text(
            t(
              '“${item.name}”将从新建选项中移除，已有客户仍保留该状态。',
              'Remove “${item.name}” from new-customer choices. Existing customers keep this status.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              key: const ValueKey('customer-status-confirm-delete'),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t('删除', 'Delete')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await ref
          .read(customerRepositoryProvider)
          .setStatusActive(item.id, active: false);
      if (mounted && widget.value == item.id) widget.onChanged(null);
    } catch (failure) {
      if (mounted) setState(() => error = context.flyError(failure));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = ref.watch(customerStatusesProvider);
    final enabled = widget.enabled && !working;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        statuses.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(context.flyError(e)),
          data: (items) => Wrap(
            spacing: isMobilePlatform ? 8 : 0,
            runSpacing: isMobilePlatform ? 8 : 0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final item in items)
                if (isMobilePlatform)
                  choice(item, enabled: enabled)
                else
                  desktopChoice(item, enabled: enabled),
              if (!isMobilePlatform)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: IconButton.outlined(
                    key: const ValueKey('customer-create-status-add'),
                    tooltip: t('新增客户状态', 'Add customer status'),
                    onPressed: enabled ? () => edit() : null,
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(32),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.standard,
                    ),
                    icon: const Icon(Icons.add, size: 18),
                  ),
                ),
            ],
          ),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  Widget choice(CustomerStatus item, {required bool enabled}) => ChoiceChip(
    key: ValueKey('customer-create-status-${item.id}'),
    label: Text(
      CustomerLifecycle.label(
        item.id,
        zh: context.l10n.isZh,
        customName: item.name,
      ),
    ),
    materialTapTargetSize: isMobilePlatform
        ? MaterialTapTargetSize.padded
        : MaterialTapTargetSize.shrinkWrap,
    selected: widget.value == item.id,
    onSelected: enabled ? (_) => widget.onChanged(item.id) : null,
  );

  Widget desktopChoice(CustomerStatus item, {required bool enabled}) {
    final colors = Theme.of(context).colorScheme;
    // The corner badge uses its own small hit box; chip padding supplies the
    // original eight-pixel visual gap without widening every status label.
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 8),
          child: Tooltip(
            message: t('双击编辑状态', 'Double-click to edit'),
            child: GestureDetector(
              onDoubleTap: enabled ? () => edit(item) : null,
              child: choice(item, enabled: enabled),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: SizedBox.square(
            dimension: 20,
            child: IconButton(
              key: ValueKey('customer-status-delete-${item.id}'),
              tooltip: t('删除状态：${item.name}', 'Delete status: ${item.name}'),
              onPressed: enabled ? () => remove(item) : null,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(20),
                fixedSize: const Size.square(20),
                maximumSize: const Size.square(20),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                foregroundColor: colors.error,
                backgroundColor: colors.surface,
                hoverColor: colors.error.withValues(alpha: .08),
                highlightColor: colors.error.withValues(alpha: .12),
                side: BorderSide(color: colors.error.withValues(alpha: .22)),
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.close, size: 11),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusNameDialog extends ConsumerStatefulWidget {
  const _StatusNameDialog({this.item});
  final CustomerStatus? item;
  @override
  ConsumerState<_StatusNameDialog> createState() => _StatusNameDialogState();
}

class _StatusNameDialogState extends ConsumerState<_StatusNameDialog> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.item?.name ?? '');
  bool busy = false;
  String? error;
  String t(String zh, String en) => context.l10n.isZh ? zh : en;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(customerRepositoryProvider);
      final item = widget.item;
      final String id;
      if (item == null) {
        id = (await repo.createStatus(name.text)).id;
      } else {
        await repo.renameStatus(item.id, name.text);
        id = item.id;
      }
      if (mounted) Navigator.pop(context, id);
    } catch (failure) {
      if (mounted) setState(() => error = context.flyError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        widget.item == null
            ? t('新增客户状态', 'Add customer status')
            : t('编辑客户状态', 'Edit customer status'),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Form(
            key: form,
            child: TextFormField(
              key: const ValueKey('customer-status-name'),
              controller: name,
              enabled: !busy,
              autofocus: true,
              decoration: InputDecoration(
                labelText: t('状态名称', 'Status name'),
                errorText: error,
              ),
              validator: (value) {
                try {
                  DriftCustomerRepository.checkedStatusName(value ?? '');
                  return null;
                } catch (_) {
                  return t(
                    '请填写1–120字的状态名称',
                    'Enter a status name of 1–120 characters',
                  );
                }
              },
              onFieldSubmitted: (_) => save(),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(t('取消', 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('customer-status-save'),
          onPressed: busy ? null : save,
          child: Text(t('保存', 'Save')),
        ),
      ],
    ),
  );
}
