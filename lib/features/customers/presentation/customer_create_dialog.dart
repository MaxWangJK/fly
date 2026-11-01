import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../l10n/service_error_copy.dart';
import '../domain/customer.dart';
import '../domain/customer_lifecycle.dart';
import 'customer_providers.dart';

class CustomerCreateDialog extends ConsumerStatefulWidget {
  const CustomerCreateDialog({this.categoryId, super.key});
  final String? categoryId;
  @override
  ConsumerState<CustomerCreateDialog> createState() =>
      _CustomerCreateDialogState();
}

class _CustomerCreateDialogState extends ConsumerState<CustomerCreateDialog> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      country = TextEditingController(),
      source = TextEditingController();
  String? category, status, error;
  bool busy = false, attempted = false;
  String t(String zh, String en) => context.l10n.isZh ? zh : en;
  @override
  void initState() {
    super.initState();
    category = widget.categoryId;
  }

  @override
  void dispose() {
    name.dispose();
    country.dispose();
    source.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      attempted = true;
      error = null;
    });
    if (!form.currentState!.validate() ||
        category == null ||
        status == null ||
        busy) {
      return;
    }
    setState(() => busy = true);
    try {
      final customer = await ref
          .read(customerRepositoryProvider)
          .createCustomer(
            name: name.text,
            country: country.text,
            categoryId: category,
            statusId: status,
            source: source.text,
          );
      if (mounted) Navigator.pop(context, customer);
    } catch (failure) {
      if (mounted) setState(() => error = context.flyError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget heading(String label, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      '$label${required ? ' *' : ''}',
      style: Theme.of(context).textTheme.labelLarge,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(customerCategoriesProvider);
    final sources =
        ref.watch(customerSourcesProvider).valueOrNull ?? <CustomerSource>[];
    final colors = Theme.of(context).colorScheme;
    String sourceLabel(String value) => switch (value) {
      'Exhibition' => t('展会', 'Exhibition'),
      'Customs data' => t('海关数据', 'Customs data'),
      'Referral' => t('朋友介绍', 'Referral'),
      'Website' => t('网站', 'Website'),
      'Existing Customer' => t('老客户介绍', 'Existing customer'),
      'Other' => t('其他', 'Other'),
      _ => value,
    };
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(t('新建客户', 'New customer')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              autovalidateMode: attempted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const ValueKey('customer-quick-add-input'),
                    controller: name,
                    enabled: !busy,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: t('客户姓名 *', 'Customer name *'),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? t('请填写客户姓名', 'Enter a customer name')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('customer-create-country'),
                    controller: country,
                    enabled: !busy,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: t('国家 *', 'Country *'),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? t('请填写国家', 'Enter a country')
                        : null,
                  ),
                  heading(t('客户级别', 'Customer category'), required: true),
                  categories.when(
                    data: (items) => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in items)
                          ChoiceChip(
                            key: ValueKey(
                              'customer-create-category-${item.id}',
                            ),
                            label: Text(item.name),
                            selected: category == item.id,
                            onSelected: busy
                                ? null
                                : (_) => setState(() => category = item.id),
                          ),
                      ],
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text(context.flyError(e)),
                  ),
                  if (attempted && category == null)
                    Text(
                      t('请选择客户级别', 'Choose a category'),
                      style: TextStyle(color: colors.error),
                    ),
                  heading(t('客户状态', 'Customer status'), required: true),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in CustomerLifecycle.stages)
                        ChoiceChip(
                          key: ValueKey('customer-create-status-${item.$1}'),
                          label: Text(context.l10n.isZh ? item.$2 : item.$3),
                          selected: status == item.$1,
                          onSelected: busy
                              ? null
                              : (_) => setState(() => status = item.$1),
                        ),
                    ],
                  ),
                  if (attempted && status == null)
                    Text(
                      t('请选择客户状态', 'Choose a status'),
                      style: TextStyle(color: colors.error),
                    ),
                  heading(t('客户来源（选填）', 'Source (optional)')),
                  TextField(
                    key: const ValueKey('customer-create-source'),
                    controller: source,
                    enabled: !busy,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: t(
                        '输入来源，或点选下方标签',
                        'Type a source or choose a tag',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final item in sources)
                        ChoiceChip(
                          label: Text(sourceLabel(item.name)),
                          selected:
                              source.text.trim().toLowerCase() ==
                              item.name.toLowerCase(),
                          onSelected: busy
                              ? null
                              : (selected) => setState(
                                  () => source.text = selected ? item.name : '',
                                ),
                        ),
                    ],
                  ),
                  if (source.text.trim().isNotEmpty &&
                      !sources.any(
                        (s) =>
                            s.name.toLowerCase() ==
                            source.text.trim().toLowerCase(),
                      ))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        t(
                          '创建时保存为新的来源标签',
                          'Saved as a new source tag when you create the customer',
                        ),
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
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
            key: const ValueKey('phone-create-customer'),
            onPressed: busy ? null : submit,
            child: Text(t('创建', 'Create')),
          ),
        ],
      ),
    );
  }
}
