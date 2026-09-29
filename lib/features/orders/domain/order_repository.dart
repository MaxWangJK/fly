import 'order.dart';

abstract interface class OrderRepository {
  Stream<List<SalesOrder>> watchOrders(OrderQuery query);
  Stream<SalesOrder?> watchOrder(String orderId);
  Stream<List<OrderStatusConfig>> watchStatuses({bool includeInactive = false});
  Stream<List<OrderProductionItem>> watchItems(String orderId);
  Stream<List<OrderPayment>> watchPayments(String orderId);
  Stream<List<OrderCostEntry>> watchCostEntries(String orderId);
  Stream<List<OrderFile>> watchFiles(String orderId);
  Stream<List<OrderNote>> watchNotes(
    String orderId, {
    String search = '',
    int limit = 20,
    int offset = 0,
  });
  Stream<OrderNote?> watchLatestNote(String orderId);
  Stream<List<OrderTag>> watchOrderTags(String orderId);
  Stream<List<OrderTag>> watchAllTags({bool includeInactive = false});
  Stream<List<OrderTag>> watchPopularTags({int limit = 8});
  Stream<List<Factory>> watchFactories();
  Stream<List<Product>> watchProducts();

  Future<SalesOrder> createOrder({
    required String customerId,
    String? orderNumber,
  });
  Future<void> saveOrder(SalesOrder order);
  Future<void> setFinancialCurrency(String orderId, String currency);
  Future<void> softDeleteOrder(String orderId);
  Future<void> restoreOrder(String orderId);

  Future<OrderStatusConfig> createStatus(String name, {int? colorValue});
  Future<void> renameStatus(String statusId, String name);
  Future<void> setStatusActive(String statusId, {required bool active});
  Future<void> setStatusColor(String statusId, int colorValue);
  Future<void> reorderStatuses(List<String> orderedIds);

  Future<OrderTag> findOrCreateTag(String name, {int? colorValue});
  Future<void> setOrderTags(String orderId, Iterable<String> tagIds);
  Future<void> renameTag(String tagId, String name);
  Future<void> setTagActive(String tagId, {required bool active});
  Future<void> deleteTag(String tagId);

  Future<Factory> findOrCreateFactory(String name, {int? colorValue});
  Future<Product> findOrCreateProduct(String name, {String unit});
  Future<OrderProductionItem> addProductionItem(
    String orderId, {
    required String factoryName,
    required String productName,
    int quantityMilli,
    String unit,
    int unitPrice,
    int salesAmount,
    int factoryCost,
    String factoryCostCurrency = 'CNY',
  });
  Future<void> saveProductionItem(
    OrderProductionItem item, {
    required String factoryName,
    required String productName,
  });
  Future<void> updateFactoryOrderStatus(
    String itemId,
    FactoryOrderStatus status,
  );
  Future<void> removeProductionItem(String itemId);

  Future<OrderNote> addNote(String orderId, {required String content});
  Future<void> saveNote(OrderNote note);
  Future<void> softDeleteNote(String noteId);

  Future<OrderPayment> addPayment(
    String orderId, {
    required int amount,
    required String currency,
    required String paymentType,
    required DateTime paidAt,
    String method,
    String note,
    String? attachmentId,
  });
  Future<void> savePayment(OrderPayment payment);
  Future<void> removePayment(String paymentId);

  Future<OrderCostEntry> addCostEntry(
    String orderId, {
    required int amountMinor,
    required String currency,
    required String costType,
    required DateTime occurredAt,
    String? attachmentId,
  });
  Future<void> saveCostEntry(OrderCostEntry entry);
  Future<void> removeCostEntry(String entryId);

  Future<OrderFile> addFileMetadata({
    required String orderId,
    String? paymentId,
    required String fileName,
    required String originalName,
    required OrderDocumentType documentType,
    required String localRelativePath,
    required int fileSize,
    required String mimeType,
  });
  Future<void> changeFileDocumentType(
    String fileId,
    OrderDocumentType documentType,
  );
  Future<void> removeFile(String fileId);
}
