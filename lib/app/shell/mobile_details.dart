import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/customers/presentation/customer_detail_panel.dart';
import '../../features/customers/presentation/customer_extension_panel.dart';
import '../../features/customers/presentation/customer_providers.dart';
import '../../features/orders/presentation/order_detail_panel.dart';
import '../../features/orders/presentation/order_providers.dart';
import '../../features/tasks/presentation/task_detail_panel.dart';
import '../../l10n/fly_localizations.dart';

Future<void> showWorkspaceSheet(BuildContext context, Widget child) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .9,
          child: child,
        ),
      ),
    );

Widget sheetContent(
  BuildContext context,
  String title,
  Widget body, {
  VoidCallback? onBack,
  Key? key,
}) => Column(
  key: key,
  children: [
    Row(
      children: [
        if (onBack != null)
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          key: const ValueKey('workspace-sheet-close'),
          tooltip: context.l10n.isZh ? '关闭' : 'Close',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    Expanded(child: body),
  ],
);

Future<void> showCustomerDetailSheet(BuildContext context, String id) {
  final container = ProviderScope.containerOf(context);
  container.read(selectedCustomerIdProvider.notifier).state = id;
  container.read(customerDetailExtensionProvider.notifier).state =
      DetailExtensionType.none;
  return showWorkspaceSheet(
    context,
    Consumer(
      builder: (context, ref, _) {
        final currentId = ref.watch(selectedCustomerIdProvider) ?? id;
        final type = ref.watch(customerDetailExtensionProvider);
        void back() =>
            ref.read(customerDetailExtensionProvider.notifier).state =
                DetailExtensionType.none;
        return sheetContent(
          context,
          context.l10n.isZh ? '客户详情' : 'Customer details',
          type == DetailExtensionType.none
              ? CustomerDetailPanel(customerId: currentId)
              : CustomerExtensionPanel(
                  customerId: currentId,
                  type: type,
                  onClose: back,
                ),
          onBack: type == DetailExtensionType.none ? null : back,
          key: const ValueKey('customer-detail-sheet'),
        );
      },
    ),
  );
}

Future<void> showOrderDetailSheet(BuildContext context, String id) {
  final container = ProviderScope.containerOf(context);
  container.read(selectedOrderIdProvider.notifier).state = id;
  container.read(orderExtensionProvider.notifier).state =
      OrderExtensionType.none;
  return showWorkspaceSheet(
    context,
    Consumer(
      builder: (context, ref, _) {
        final type = ref.watch(orderExtensionProvider);
        void back() => ref.read(orderExtensionProvider.notifier).state =
            OrderExtensionType.none;
        return sheetContent(
          context,
          context.l10n.isZh ? '订单详情' : 'Order details',
          type == OrderExtensionType.none
              ? OrderDetailPanel(orderId: id)
              : OrderExtensionPanel(orderId: id, type: type, onClose: back),
          onBack: type == OrderExtensionType.none ? null : back,
          key: const ValueKey('order-detail-sheet'),
        );
      },
    ),
  );
}

Future<void> showTaskDetailSheet(BuildContext context, String id) =>
    showWorkspaceSheet(
      context,
      sheetContent(
        context,
        context.l10n.isZh ? '任务详情' : 'Task details',
        TaskDetailPanel(taskId: id),
      ),
    );
