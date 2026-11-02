import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../l10n/service_error_copy.dart';
import '../domain/order_lifecycle.dart';
import 'order_providers.dart';

class OrderCreateDialog extends ConsumerStatefulWidget {
  const OrderCreateDialog({
    required this.customerId,
    required this.customerName,
    super.key,
  });
  final String customerId, customerName;
  @override
  ConsumerState<OrderCreateDialog> createState() => _OrderCreateDialogState();
}

class _OrderCreateDialogState extends ConsumerState<OrderCreateDialog> {
  final form = GlobalKey<FormState>();
  final number = TextEditingController();
  String status = OrderLifecycle.pending;
  String? error;
  bool busy = false;
  String t(String zh, String en) => context.l10n.isZh ? zh : en;
  @override
  void dispose() {
    number.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final order = await ref
          .read(orderRepositoryProvider)
          .createOrder(
            customerId: widget.customerId,
            orderNumber: number.text,
            statusId: status,
          );
      if (mounted) Navigator.pop(context, order);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError && e.message == '订单号已存在，请使用其他PI发票号'
              ? t(
                  e.message,
                  'This order number already exists. Use another PI invoice number.',
                )
              : context.flyError(e),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(t('新建订单', 'New order')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.customerName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('create-order-number'),
                  controller: number,
                  autofocus: true,
                  enabled: !busy,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: t(
                      'PI发票号（订单号） *',
                      'PI invoice number (order number) *',
                    ),
                  ),
                  onFieldSubmitted: (_) => submit(),
                  onChanged: (_) {
                    if (error != null) setState(() => error = null);
                  },
                  validator: (v) => v == null || v.trim().isEmpty
                      ? t('请填写PI发票号', 'Enter a PI invoice number')
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  t('订单状态', 'Order status'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final stage in OrderLifecycle.stages)
                      ChoiceChip(
                        key: ValueKey('create-order-status-${stage.$1}'),
                        label: Text(context.l10n.isZh ? stage.$2 : stage.$3),
                        selected: status == stage.$1,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => status = stage.$1),
                      ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (busy) const LinearProgressIndicator(),
              ],
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
          key: const ValueKey('create-order-submit'),
          onPressed: busy ? null : submit,
          child: Text(t('创建订单', 'Create order')),
        ),
      ],
    ),
  );
}
