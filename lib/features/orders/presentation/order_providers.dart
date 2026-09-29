import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tasks/presentation/task_providers.dart';
import '../../../core/storage/data_root_providers.dart';
import '../data/drift_order_repository.dart';
import '../data/order_file_service.dart';
import '../domain/order.dart';
import '../domain/order_repository.dart';

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => DriftOrderRepository(ref.watch(databaseProvider)),
);
final orderFileStorageProvider = Provider<OrderFileStorage>(
  (ref) => LocalOrderFileStorage(dataRootPath: ref.watch(dataRootPathProvider)),
);
final orderFileOpenerProvider = Provider<OrderFileOpener>(
  (ref) => PlatformOrderFileOpener(),
);

final selectedOrderIdProvider = StateProvider<String?>((ref) => null);

enum OrderExtensionType { none, orderDetails, financial, notes }

final orderExtensionProvider = StateProvider<OrderExtensionType>(
  (ref) => OrderExtensionType.none,
);
final orderCustomerFilterProvider = StateProvider<String?>((ref) => null);
final orderSearchProvider = StateProvider<String>((ref) => '');
final orderSortProvider = StateProvider<OrderSort>(
  (ref) => OrderSort.createdAt,
);

final ordersProvider = StreamProvider.family<List<SalesOrder>, OrderQuery>(
  (ref, query) => ref.watch(orderRepositoryProvider).watchOrders(query),
);
final orderListProvider =
    StreamProvider.family<
      List<SalesOrder>,
      ({OrderProjection projection, String? tagId})
    >((ref, route) {
      final query = OrderQuery(
        projection: route.projection,
        tagId: route.tagId,
        customerId: ref.watch(orderCustomerFilterProvider),
        search: ref.watch(orderSearchProvider),
        sort: ref.watch(orderSortProvider),
      );
      return ref.watch(orderRepositoryProvider).watchOrders(query);
    });
final customerOrdersProvider = StreamProvider.family<List<SalesOrder>, String>(
  (ref, customerId) => ref
      .watch(orderRepositoryProvider)
      .watchOrders(
        OrderQuery(projection: OrderProjection.all, customerId: customerId),
      ),
);
final orderProvider = StreamProvider.family<SalesOrder?, String>(
  (ref, id) => ref.watch(orderRepositoryProvider).watchOrder(id),
);
final orderStatusesProvider = StreamProvider<List<OrderStatusConfig>>(
  (ref) => ref.watch(orderRepositoryProvider).watchStatuses(),
);
final allOrderStatusesProvider = StreamProvider<List<OrderStatusConfig>>(
  (ref) =>
      ref.watch(orderRepositoryProvider).watchStatuses(includeInactive: true),
);
final allOrderTagsProvider = StreamProvider<List<OrderTag>>(
  (ref) => ref.watch(orderRepositoryProvider).watchAllTags(),
);
final allOrderTagsIncludingInactiveProvider = StreamProvider<List<OrderTag>>(
  (ref) =>
      ref.watch(orderRepositoryProvider).watchAllTags(includeInactive: true),
);
final popularOrderTagsProvider = StreamProvider<List<OrderTag>>(
  (ref) => ref.watch(orderRepositoryProvider).watchPopularTags(),
);
final orderTagsProvider = StreamProvider.family<List<OrderTag>, String>(
  (ref, id) => ref.watch(orderRepositoryProvider).watchOrderTags(id),
);
final orderItemsProvider =
    StreamProvider.family<List<OrderProductionItem>, String>(
      (ref, id) => ref.watch(orderRepositoryProvider).watchItems(id),
    );
final orderPaymentsProvider = StreamProvider.family<List<OrderPayment>, String>(
  (ref, id) => ref.watch(orderRepositoryProvider).watchPayments(id),
);
final orderCostEntriesProvider =
    StreamProvider.family<List<OrderCostEntry>, String>(
      (ref, id) => ref.watch(orderRepositoryProvider).watchCostEntries(id),
    );
final selectedFinancialCurrencyProvider = StateProvider.family<String, String>((
  ref,
  orderId,
) {
  final currency = ref.watch(orderProvider(orderId)).valueOrNull?.currency;
  return currency?.toUpperCase() == 'CNY' || currency?.toUpperCase() == 'RMB'
      ? 'CNY'
      : 'USD';
});
final orderFilesProvider = StreamProvider.family<List<OrderFile>, String>(
  (ref, id) => ref.watch(orderRepositoryProvider).watchFiles(id),
);
final latestOrderNoteProvider = StreamProvider.family<OrderNote?, String>(
  (ref, id) => ref.watch(orderRepositoryProvider).watchLatestNote(id),
);
final orderNotesProvider =
    StreamProvider.family<
      List<OrderNote>,
      ({String orderId, String search, int limit})
    >(
      (ref, query) => ref
          .watch(orderRepositoryProvider)
          .watchNotes(query.orderId, search: query.search, limit: query.limit),
    );
final factoriesProvider = StreamProvider<List<Factory>>(
  (ref) => ref.watch(orderRepositoryProvider).watchFactories(),
);
final productsProvider = StreamProvider<List<Product>>(
  (ref) => ref.watch(orderRepositoryProvider).watchProducts(),
);
