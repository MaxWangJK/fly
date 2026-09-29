import '../../../shared/domain/priority.dart';

enum OrderProjection {
  all,
  important,
  urgent,
  outstanding,
  normal,
  tag,
  deleted,
}

enum OrderSort {
  createdAt,
  manual,
  orderDate,
  deliveryDate,
  priority,
  status,
  customer,
  amount,
  profit,
}

enum FactoryOrderStatus { notPlaced, notified, confirmed, producing, completed }

enum OrderDocumentType { pi, ci, pl, co, payment, image, other }

int orderDisplayRank(SalesOrder order) {
  if (order.urgency) return 0;
  if (order.importance) return 1;
  return 2;
}

class OrderQuery {
  const OrderQuery({
    required this.projection,
    this.tagId,
    this.customerId,
    this.search = '',
    this.sort = OrderSort.createdAt,
  });

  final OrderProjection projection;
  final String? tagId;
  final String? customerId;
  final String search;
  final OrderSort sort;

  OrderQuery copyWith({
    OrderProjection? projection,
    String? tagId,
    Object? customerId = _unset,
    String? search,
    OrderSort? sort,
  }) => OrderQuery(
    projection: projection ?? this.projection,
    tagId: tagId ?? this.tagId,
    customerId: identical(customerId, _unset)
        ? this.customerId
        : customerId as String?,
    search: search ?? this.search,
    sort: sort ?? this.sort,
  );
}

class SalesOrder {
  const SalesOrder({
    required this.id,
    required this.orderNumber,
    required this.priority,
    required this.importance,
    required this.urgency,
    required this.currency,
    required this.baseProfitCurrency,
    required this.exchangeRateMicros,
    required this.salesAmount,
    required this.taxRefund,
    this.taxRefundCurrency = 'CNY',
    required this.inlandCost,
    required this.portCharges,
    required this.otherCost,
    required this.otherIncome,
    required this.notes,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.customerId,
    this.statusId,
    this.orderDate,
    this.deliveryDate,
    this.deletedAt,
  });

  final String id;
  final String orderNumber;
  final String? customerId;
  final String? statusId;
  final PriorityLevel priority;
  final bool importance;
  final bool urgency;
  final String currency;
  final String baseProfitCurrency;
  final int exchangeRateMicros;
  final int salesAmount;
  final int taxRefund;
  final String taxRefundCurrency;
  final int inlandCost;
  final int portCharges;
  final int otherCost;
  final int otherIncome;
  final DateTime? orderDate;
  final DateTime? deliveryDate;
  final String notes;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  SalesOrder copyWith({
    String? id,
    String? orderNumber,
    Object? customerId = _unset,
    Object? statusId = _unset,
    PriorityLevel? priority,
    bool? importance,
    bool? urgency,
    String? currency,
    String? baseProfitCurrency,
    int? exchangeRateMicros,
    int? salesAmount,
    int? taxRefund,
    String? taxRefundCurrency,
    int? inlandCost,
    int? portCharges,
    int? otherCost,
    int? otherIncome,
    Object? orderDate = _unset,
    Object? deliveryDate = _unset,
    String? notes,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    int? version,
  }) => SalesOrder(
    id: id ?? this.id,
    orderNumber: orderNumber ?? this.orderNumber,
    customerId: identical(customerId, _unset)
        ? this.customerId
        : customerId as String?,
    statusId: identical(statusId, _unset) ? this.statusId : statusId as String?,
    priority: priority ?? this.priority,
    importance: importance ?? this.importance,
    urgency: urgency ?? this.urgency,
    currency: currency ?? this.currency,
    baseProfitCurrency: baseProfitCurrency ?? this.baseProfitCurrency,
    exchangeRateMicros: exchangeRateMicros ?? this.exchangeRateMicros,
    salesAmount: salesAmount ?? this.salesAmount,
    taxRefund: taxRefund ?? this.taxRefund,
    taxRefundCurrency: taxRefundCurrency ?? this.taxRefundCurrency,
    inlandCost: inlandCost ?? this.inlandCost,
    portCharges: portCharges ?? this.portCharges,
    otherCost: otherCost ?? this.otherCost,
    otherIncome: otherIncome ?? this.otherIncome,
    orderDate: identical(orderDate, _unset)
        ? this.orderDate
        : orderDate as DateTime?,
    deliveryDate: identical(deliveryDate, _unset)
        ? this.deliveryDate
        : deliveryDate as DateTime?,
    notes: notes ?? this.notes,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: identical(deletedAt, _unset)
        ? this.deletedAt
        : deletedAt as DateTime?,
    version: version ?? this.version,
  );
}

class OrderStatusConfig {
  const OrderStatusConfig({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.isActive,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final int colorValue;
  final bool isActive;
  final int sortOrder;
}

class OrderTag {
  const OrderTag({
    required this.id,
    required this.name,
    required this.colorValue,
    this.isActive = true,
  });

  final String id;
  final String name;
  final int colorValue;
  final bool isActive;

  OrderTag copyWith({bool? isActive}) => OrderTag(
    id: id,
    name: name,
    colorValue: colorValue,
    isActive: isActive ?? this.isActive,
  );
}

class Factory {
  const Factory({
    required this.id,
    required this.name,
    required this.contact,
    required this.phone,
    required this.address,
    required this.note,
    required this.colorValue,
  });

  final String id;
  final String name;
  final String contact;
  final String phone;
  final String address;
  final String note;
  final int colorValue;
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.unit,
    required this.note,
  });

  final String id;
  final String name;
  final String unit;
  final String note;
}

class OrderProductionItem {
  const OrderProductionItem({
    required this.id,
    required this.orderId,
    required this.quantityMilli,
    required this.unit,
    required this.unitPrice,
    required this.salesAmount,
    required this.factoryCost,
    this.factoryCostCurrency = 'CNY',
    required this.productionStatus,
    required this.factoryOrderStatus,
    required this.colorValue,
    required this.note,
    required this.sortOrder,
    this.factoryId,
    this.productId,
  });

  final String id;
  final String orderId;
  final String? factoryId;
  final String? productId;
  final int quantityMilli;
  final String unit;
  final int unitPrice;
  final int salesAmount;
  final int factoryCost;
  final String factoryCostCurrency;
  final String productionStatus;
  final FactoryOrderStatus factoryOrderStatus;
  final int colorValue;
  final String note;
  final int sortOrder;

  OrderProductionItem copyWith({
    String? factoryId,
    String? productId,
    int? quantityMilli,
    String? unit,
    int? unitPrice,
    int? salesAmount,
    int? factoryCost,
    String? factoryCostCurrency,
    String? productionStatus,
    FactoryOrderStatus? factoryOrderStatus,
    int? colorValue,
    String? note,
  }) => OrderProductionItem(
    id: id,
    orderId: orderId,
    factoryId: factoryId ?? this.factoryId,
    productId: productId ?? this.productId,
    quantityMilli: quantityMilli ?? this.quantityMilli,
    unit: unit ?? this.unit,
    unitPrice: unitPrice ?? this.unitPrice,
    salesAmount: salesAmount ?? this.salesAmount,
    factoryCost: factoryCost ?? this.factoryCost,
    factoryCostCurrency: factoryCostCurrency ?? this.factoryCostCurrency,
    productionStatus: productionStatus ?? this.productionStatus,
    factoryOrderStatus: factoryOrderStatus ?? this.factoryOrderStatus,
    colorValue: colorValue ?? this.colorValue,
    note: note ?? this.note,
    sortOrder: sortOrder,
  );
}

class OrderPayment {
  const OrderPayment({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.paymentType,
    required this.paidAt,
    required this.method,
    required this.note,
    this.attachmentId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String orderId;
  final int amount;
  final String currency;
  final String paymentType;
  final DateTime paidAt;
  final String method;
  final String note;
  final String? attachmentId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  OrderPayment copyWith({
    int? amount,
    String? currency,
    String? paymentType,
    DateTime? paidAt,
    Object? attachmentId = _unset,
    DateTime? updatedAt,
  }) => OrderPayment(
    id: id,
    orderId: orderId,
    amount: amount ?? this.amount,
    currency: currency ?? this.currency,
    paymentType: paymentType ?? this.paymentType,
    paidAt: paidAt ?? this.paidAt,
    method: method,
    note: note,
    attachmentId: identical(attachmentId, _unset)
        ? this.attachmentId
        : attachmentId as String?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class OrderCostEntry {
  const OrderCostEntry({
    required this.id,
    required this.orderId,
    required this.amountMinor,
    required this.currency,
    required this.costType,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    this.attachmentId,
  });

  final String id;
  final String orderId;
  final int amountMinor;
  final String currency;
  final String costType;
  final DateTime occurredAt;
  final String? attachmentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  OrderCostEntry copyWith({
    int? amountMinor,
    String? currency,
    String? costType,
    DateTime? occurredAt,
    Object? attachmentId = _unset,
    DateTime? updatedAt,
  }) => OrderCostEntry(
    id: id,
    orderId: orderId,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    costType: costType ?? this.costType,
    occurredAt: occurredAt ?? this.occurredAt,
    attachmentId: identical(attachmentId, _unset)
        ? this.attachmentId
        : attachmentId as String?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class OrderFile {
  const OrderFile({
    required this.id,
    required this.orderId,
    required this.fileName,
    required this.originalName,
    required this.documentType,
    required this.localRelativePath,
    required this.fileSize,
    required this.mimeType,
    required this.createdAt,
    this.paymentId,
  });

  final String id;
  final String orderId;
  final String? paymentId;
  final String fileName;
  final String originalName;
  final OrderDocumentType documentType;
  final String localRelativePath;
  final int fileSize;
  final String mimeType;
  final DateTime createdAt;
}

class OrderNote {
  const OrderNote({
    required this.id,
    required this.orderId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.colorValue,
    required this.sortOrder,
    required this.version,
    this.deletedAt,
  });

  final String id;
  final String orderId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int colorValue;
  final int sortOrder;
  final DateTime? deletedAt;
  final int version;

  OrderNote copyWith({
    String? content,
    DateTime? updatedAt,
    int? colorValue,
    int? sortOrder,
    DateTime? deletedAt,
    int? version,
  }) => OrderNote(
    id: id,
    orderId: orderId,
    content: content ?? this.content,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    colorValue: colorValue ?? this.colorValue,
    sortOrder: sortOrder ?? this.sortOrder,
    deletedAt: deletedAt ?? this.deletedAt,
    version: version ?? this.version,
  );
}

class OrderFinancialSummary {
  const OrderFinancialSummary({
    required this.order,
    required this.items,
    required this.payments,
    this.costEntries = const [],
    String? accountingCurrency,
  }) : accountingCurrency = accountingCurrency ?? 'CNY';

  final SalesOrder order;
  final List<OrderProductionItem> items;
  final List<OrderPayment> payments;
  final List<OrderCostEntry> costEntries;
  final String accountingCurrency;

  String get currency => 'CNY';

  static String normalizeCurrency(String value) {
    final upper = value.trim().toUpperCase();
    return upper == 'RMB' ? 'CNY' : upper;
  }

  int get roundedExchangeRateMicros =>
      roundExchangeRateMicros(order.exchangeRateMicros);

  double? get usdToRmbRate => roundedExchangeRateMicros <= 0
      ? null
      : roundedExchangeRateMicros / 1000000;

  int? toRmb(int amount, String amountCurrency) {
    if (amount == 0) return 0;
    final normalized = normalizeCurrency(amountCurrency);
    if (normalized == 'CNY') return amount;
    if (normalized != 'USD' || roundedExchangeRateMicros <= 0) return null;
    return (amount * roundedExchangeRateMicros / 1000000).round();
  }

  int? convert(int amount, String from, String to) {
    final normalizedFrom = normalizeCurrency(from);
    final normalizedTo = normalizeCurrency(to);
    if (amount == 0 || normalizedFrom == normalizedTo) return amount;
    if (roundedExchangeRateMicros <= 0) return null;
    if (normalizedFrom == 'USD' && normalizedTo == 'CNY') {
      return (amount * roundedExchangeRateMicros / 1000000).round();
    }
    if (normalizedFrom == 'CNY' && normalizedTo == 'USD') {
      return (amount * 1000000 / roundedExchangeRateMicros).round();
    }
    return null;
  }

  Map<String, int> _totalsByCurrency(Iterable<(int, String)> values) {
    final result = <String, int>{};
    for (final value in values) {
      final code = normalizeCurrency(value.$2);
      result[code] = (result[code] ?? 0) + value.$1;
    }
    return result;
  }

  Map<String, int> get receivedByCurrency => _totalsByCurrency(
    payments.map((payment) => (payment.amount, payment.currency)),
  );

  Map<String, int> get costByCurrency => _totalsByCurrency([
    for (final item in items) (item.factoryCost, item.factoryCostCurrency),
    for (final entry in costEntries) (entry.amountMinor, entry.currency),
    if (costEntries.isEmpty &&
        order.inlandCost + order.portCharges + order.otherCost != 0)
      (
        order.inlandCost + order.portCharges + order.otherCost,
        order.baseProfitCurrency,
      ),
  ]);

  int? _sumRmb(Iterable<(int, String)> values) {
    var result = 0;
    for (final value in values) {
      final converted = toRmb(value.$1, value.$2);
      if (converted == null) return null;
      result += converted;
    }
    return result;
  }

  int get factoryCost => items.fold(0, (sum, item) => sum + item.factoryCost);
  int get dynamicCost =>
      costEntries.fold(0, (sum, entry) => sum + entry.amountMinor);
  int get legacyCost => costEntries.isNotEmpty
      ? 0
      : order.inlandCost + order.portCharges + order.otherCost;
  int get totalCost => factoryCost + dynamicCost + legacyCost;
  int get receivedAmount =>
      payments.fold(0, (sum, payment) => sum + payment.amount);
  int get receivedDeposit => payments
      .where(
        (payment) =>
            payment.paymentType.trim().toLowerCase() == 'deposit' ||
            payment.paymentType.trim() == '定金',
      )
      .fold(0, (sum, payment) => sum + payment.amount);
  int get receivedBalance => payments
      .where(
        (payment) =>
            payment.paymentType.trim().toLowerCase() == 'balance' ||
            payment.paymentType.trim() == '尾款',
      )
      .fold(0, (sum, payment) => sum + payment.amount);
  int? get salesRmb => toRmb(order.salesAmount, order.currency);
  int? get salesInProfitCurrency =>
      convert(order.salesAmount, order.currency, order.baseProfitCurrency);
  int? get receivedRmb =>
      _sumRmb(payments.map((payment) => (payment.amount, payment.currency)));
  int? get totalCostRmb => _sumRmb([
    for (final item in items) (item.factoryCost, item.factoryCostCurrency),
    for (final entry in costEntries) (entry.amountMinor, entry.currency),
    if (costEntries.isEmpty && legacyCost != 0)
      (legacyCost, order.baseProfitCurrency),
  ]);
  int? get taxRefundRmb => toRmb(order.taxRefund, order.taxRefundCurrency);
  int? get otherIncomeRmb => toRmb(order.otherIncome, order.baseProfitCurrency);

  int? get receivedInSalesCurrency {
    var result = 0;
    for (final payment in payments) {
      final converted = convert(
        payment.amount,
        payment.currency,
        order.currency,
      );
      if (converted == null) return null;
      result += converted;
    }
    return result;
  }

  int? get outstandingAmount {
    final received = receivedInSalesCurrency;
    return received == null ? null : order.salesAmount - received;
  }

  int? get outstandingRmb {
    final sales = salesRmb;
    final received = receivedRmb;
    return sales == null || received == null ? null : sales - received;
  }

  bool get isFullyPaid => outstandingAmount != null && outstandingAmount! <= 0;
  int? get profit {
    final sales = salesRmb;
    final costs = totalCostRmb;
    final refund = taxRefundRmb;
    final income = otherIncomeRmb;
    if (sales == null || costs == null || refund == null || income == null) {
      return null;
    }
    return sales + refund + income - costs;
  }

  double? get profitMargin {
    final convertedSales = salesRmb;
    final value = profit;
    return convertedSales == null || convertedSales == 0 || value == null
        ? null
        : value / convertedSales;
  }
}

int roundExchangeRateMicros(int value) {
  if (value <= 0) return 0;
  return (value / 10000).round() * 10000;
}

class _Unset {
  const _Unset();
}

const _unset = _Unset();
