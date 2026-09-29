import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/data/tag_garbage_collector.dart';
import '../../../shared/domain/priority.dart';
import '../../customers/domain/customer.dart';
import '../domain/order.dart';
import '../domain/order_repository.dart';

class DriftOrderRepository implements OrderRepository {
  DriftOrderRepository(this._db);

  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  Future<List<SalesOrder>> seedDevelopmentData(
    List<Customer> customers, {
    DateTime? today,
  }) async {
    final existing = await watchOrders(
      const OrderQuery(projection: OrderProjection.all),
    ).first;
    if (existing.isNotEmpty) return existing;
    final statuses = await watchStatuses().first;
    String? status(String name) =>
        statuses.where((item) => item.name == name).firstOrNull?.id;
    Customer? customer(String name) =>
        customers.where((item) => item.name == name).firstOrNull;
    final now = today ?? DateTime.now();
    final date = DateTime(now.year, now.month, now.day);

    var jackOrder = await createOrder(
      customerId: customer('Jack Lim')!.id,
      orderNumber: 'SO-${date.year}-001',
    );
    jackOrder = jackOrder.copyWith(
      statusId: status('生产中'),
      priority: PriorityLevel.high,
      importance: false,
      urgency: true,
      baseProfitCurrency: 'CNY',
      exchangeRateMicros: 7120000,
      salesAmount: 2000000,
      taxRefund: 150000,
      orderDate: date,
      deliveryDate: date.add(const Duration(days: 35)),
      notes: '## 生产要求\n- 浅木色\n- 独立纸箱包装\n- 交期不可延误',
    );
    await saveOrder(jackOrder);
    await addNote(jackOrder.id, content: '客户要求浅木色、独立纸箱包装，交期不可延误。');
    final firstItem = await addProductionItem(
      jackOrder.id,
      factoryName: '新材料工厂',
      productName: 'WPC 格栅',
      quantityMilli: 800000,
      unit: 'pcs',
      salesAmount: 1400000,
      factoryCost: 6977600,
      factoryCostCurrency: 'CNY',
    );
    await updateFactoryOrderStatus(firstItem.id, FactoryOrderStatus.producing);
    await addProductionItem(
      jackOrder.id,
      factoryName: 'A墙板工厂',
      productName: 'UV 板',
      quantityMilli: 300000,
      unit: 'sheets',
      salesAmount: 600000,
      factoryCost: 2990400,
      factoryCostCurrency: 'CNY',
    );
    final urgent = await findOrCreateTag('急单', colorValue: 0xFFF8ECEE);
    final wpc = await findOrCreateTag('WPC', colorValue: 0xFFE9EFFB);
    await setOrderTags(jackOrder.id, [urgent.id, wpc.id]);
    await addPayment(
      jackOrder.id,
      amount: 500000,
      currency: 'USD',
      paymentType: '定金',
      paidAt: date,
    );
    await addCostEntry(
      jackOrder.id,
      amountMinor: 50000,
      currency: 'CNY',
      costType: '内陆费',
      occurredAt: date,
    );
    await addCostEntry(
      jackOrder.id,
      amountMinor: 30000,
      currency: 'CNY',
      costType: '港杂费',
      occurredAt: date,
    );
    await addCostEntry(
      jackOrder.id,
      amountMinor: 20000,
      currency: 'USD',
      costType: '其他费用',
      occurredAt: date,
    );

    var ahmedOrder = await createOrder(
      customerId: customer('Ahmed Hassan')!.id,
      orderNumber: 'SO-${date.year}-002',
    );
    ahmedOrder = ahmedOrder.copyWith(
      statusId: status('待收尾款'),
      importance: false,
      urgency: true,
      priority: PriorityLevel.medium,
      baseProfitCurrency: 'CNY',
      exchangeRateMicros: 7120000,
      salesAmount: 850000,
      orderDate: date.subtract(const Duration(days: 4)),
      deliveryDate: date.add(const Duration(days: 14)),
    );
    await saveOrder(ahmedOrder);
    final item = await addProductionItem(
      ahmedOrder.id,
      factoryName: 'UV 板工厂',
      productName: 'UV Marble Sheet',
      quantityMilli: 200000,
      unit: 'sheets',
      factoryCost: 3702400,
      factoryCostCurrency: 'CNY',
    );
    await updateFactoryOrderStatus(item.id, FactoryOrderStatus.completed);
    await addPayment(
      ahmedOrder.id,
      amount: 300000,
      currency: 'USD',
      paymentType: '定金',
      paidAt: date.subtract(const Duration(days: 3)),
    );
    await addCostEntry(
      ahmedOrder.id,
      amountMinor: 249200,
      currency: 'CNY',
      costType: '拖车费',
      occurredAt: date.subtract(const Duration(days: 3)),
    );

    Future<SalesOrder> createDemoOrder({
      required String customerName,
      required int suffix,
      required String statusName,
      required int daysAgo,
      required int deliveryIn,
      required String currency,
      required int salesAmount,
      required PriorityLevel priority,
      required bool important,
      required bool urgent,
      required String factory,
      required String product,
      required int quantityMilli,
      required String unit,
      required int factoryCost,
    }) async {
      var order = await createOrder(
        customerId: customer(customerName)!.id,
        orderNumber: 'SO-${date.year}-${suffix.toString().padLeft(3, '0')}',
      );
      order = order.copyWith(
        statusId: status(statusName),
        currency: currency,
        baseProfitCurrency: 'CNY',
        exchangeRateMicros: currency.toUpperCase() == 'USD' ? 7120000 : 0,
        salesAmount: salesAmount,
        priority: priority,
        importance: important,
        urgency: urgent,
        orderDate: date.subtract(Duration(days: daysAgo)),
        deliveryDate: date.add(Duration(days: deliveryIn)),
      );
      await saveOrder(order);
      final production = await addProductionItem(
        order.id,
        factoryName: factory,
        productName: product,
        quantityMilli: quantityMilli,
        unit: unit,
        salesAmount: salesAmount,
        factoryCost: currency.toUpperCase() == 'USD'
            ? (factoryCost * 7.12).round()
            : factoryCost,
        factoryCostCurrency: 'CNY',
      );
      if (statusName == '已完成' || statusName == '已发货') {
        await updateFactoryOrderStatus(
          production.id,
          FactoryOrderStatus.completed,
        );
      } else if (statusName == '生产中') {
        await updateFactoryOrderStatus(
          production.id,
          FactoryOrderStatus.producing,
        );
      }
      return order;
    }

    final davidOrder = await createDemoOrder(
      customerName: 'David Turner',
      suffix: 3,
      statusName: '询价',
      daysAgo: 3,
      deliveryIn: 40,
      currency: 'RMB',
      salesAmount: 11800000,
      priority: PriorityLevel.low,
      important: true,
      urgent: false,
      factory: '户外共挤工厂',
      product: 'Outdoor WPC',
      quantityMilli: 500000,
      unit: '㎡',
      factoryCost: 7600000,
    );
    final aliOrder = await createDemoOrder(
      customerName: 'Ali Faisal',
      suffix: 4,
      statusName: '已发货',
      daysAgo: 10,
      deliveryIn: 2,
      currency: 'USD',
      salesAmount: 1260000,
      priority: PriorityLevel.high,
      important: false,
      urgent: false,
      factory: '天花板工厂',
      product: 'PVC Ceiling',
      quantityMilli: 1200000,
      unit: 'pcs',
      factoryCost: 720000,
    );
    final niranOrder = await createDemoOrder(
      customerName: 'Niran Chai',
      suffix: 5,
      statusName: '已完成',
      daysAgo: 30,
      deliveryIn: -2,
      currency: 'RMB',
      salesAmount: 8600000,
      priority: PriorityLevel.low,
      important: false,
      urgent: false,
      factory: 'SPC 地板工厂',
      product: 'SPC Flooring',
      quantityMilli: 800000,
      unit: '㎡',
      factoryCost: 5900000,
    );
    final linhOrder = await createDemoOrder(
      customerName: 'Linh Nguyen',
      suffix: 6,
      statusName: '待确认',
      daysAgo: 1,
      deliveryIn: 28,
      currency: 'USD',
      salesAmount: 1580000,
      priority: PriorityLevel.medium,
      important: true,
      urgent: false,
      factory: 'A墙板工厂',
      product: 'UV Marble Sheet',
      quantityMilli: 300000,
      unit: '张',
      factoryCost: 910000,
    );
    final sampleTag = await findOrCreateTag('样品', colorValue: 0xFFF0ECF8);
    final shippedTag = await findOrCreateTag('已发货', colorValue: 0xFFEAF4EF);
    await setOrderTags(davidOrder.id, [sampleTag.id, wpc.id]);
    await setOrderTags(aliOrder.id, [shippedTag.id]);
    await addPayment(
      niranOrder.id,
      amount: niranOrder.salesAmount,
      currency: 'RMB',
      paymentType: '全款',
      paidAt: date.subtract(const Duration(days: 20)),
    );
    await addPayment(
      linhOrder.id,
      amount: 300000,
      currency: 'USD',
      paymentType: '样品费',
      paidAt: date,
    );
    return [jackOrder, ahmedOrder, davidOrder, aliOrder, niranOrder, linhOrder];
  }

  @override
  Stream<List<SalesOrder>> watchOrders(OrderQuery query) {
    final joined = _db.select(_db.orders).join([
      leftOuterJoin(
        _db.customers,
        _db.customers.id.equalsExp(_db.orders.customerId),
      ),
      leftOuterJoin(
        _db.orderProductionItems,
        _db.orderProductionItems.orderId.equalsExp(_db.orders.id) &
            _db.orderProductionItems.deletedAt.isNull(),
      ),
      leftOuterJoin(
        _db.factories,
        _db.factories.id.equalsExp(_db.orderProductionItems.factoryId),
      ),
      leftOuterJoin(
        _db.products,
        _db.products.id.equalsExp(_db.orderProductionItems.productId),
      ),
      leftOuterJoin(
        _db.orderTagLinks,
        _db.orderTagLinks.orderId.equalsExp(_db.orders.id),
      ),
      leftOuterJoin(
        _db.orderPayments,
        _db.orderPayments.orderId.equalsExp(_db.orders.id) &
            _db.orderPayments.deletedAt.isNull(),
      ),
    ]);
    if (query.projection == OrderProjection.deleted) {
      joined.where(_db.orders.deletedAt.isNotNull());
    } else {
      joined.where(_db.orders.deletedAt.isNull());
    }
    return joined.watch().map((rows) {
      final orders = <String, SalesOrder>{};
      final customerNames = <String, String>{};
      final searchableChildren = <String, Set<String>>{};
      final tagIds = <String, Set<String>>{};
      final factoryCosts = <String, int>{};
      final seenItems = <String>{};
      final seenPayments = <String>{};
      final payments = <String, List<OrderPayment>>{};
      for (final row in rows) {
        final record = row.readTable(_db.orders);
        orders.putIfAbsent(record.id, () => _mapOrder(record));
        final customer = row.readTableOrNull(_db.customers);
        if (customer != null) {
          customerNames[record.id] = '${customer.name} ${customer.companyName}';
        }
        final item = row.readTableOrNull(_db.orderProductionItems);
        if (item != null) {
          final factory = row.readTableOrNull(_db.factories);
          final product = row.readTableOrNull(_db.products);
          searchableChildren.putIfAbsent(record.id, () => <String>{})
            ..add(factory?.name ?? '')
            ..add(product?.name ?? '');
          if (seenItems.add(item.id)) {
            factoryCosts[record.id] =
                (factoryCosts[record.id] ?? 0) + item.factoryCost;
          }
        }
        final tag = row.readTableOrNull(_db.orderTagLinks);
        if (tag != null) {
          tagIds.putIfAbsent(record.id, () => <String>{}).add(tag.tagId);
        }
        final payment = row.readTableOrNull(_db.orderPayments);
        if (payment != null && seenPayments.add(payment.id)) {
          payments.putIfAbsent(record.id, () => []).add(_mapPayment(payment));
        }
      }
      final needle = query.search.trim().toLowerCase();
      final result = orders.values.where((order) {
        final projectionMatch = switch (query.projection) {
          OrderProjection.all || OrderProjection.deleted => true,
          OrderProjection.important => order.importance,
          OrderProjection.urgent => order.urgency,
          OrderProjection.outstanding =>
            (OrderFinancialSummary(
                      order: order,
                      items: const [],
                      payments: payments[order.id] ?? const [],
                    ).outstandingAmount ??
                    0) >
                0,
          OrderProjection.normal => !order.importance && !order.urgency,
          OrderProjection.tag =>
            tagIds[order.id]?.contains(query.tagId) ?? false,
        };
        if (!projectionMatch) return false;
        if (query.customerId != null && order.customerId != query.customerId) {
          return false;
        }
        if (needle.isEmpty) return true;
        final values = <String>[
          order.orderNumber,
          customerNames[order.id] ?? '',
          ...searchableChildren[order.id] ?? const <String>{},
        ];
        return values.any((value) => value.toLowerCase().contains(needle));
      }).toList();
      result.sort(
        _orderComparator(
          query.sort,
          customerNames: customerNames,
          factoryCosts: factoryCosts,
        ),
      );
      return result;
    });
  }

  @override
  Stream<SalesOrder?> watchOrder(String orderId) =>
      (_db.select(_db.orders)
            ..where((row) => row.id.equals(orderId) & row.deletedAt.isNull()))
          .watchSingleOrNull()
          .map((record) => record == null ? null : _mapOrder(record));

  @override
  Stream<List<OrderStatusConfig>> watchStatuses({
    bool includeInactive = false,
  }) {
    final query = _db.select(_db.orderStatuses)
      ..where((row) {
        final active = row.deletedAt.isNull();
        return includeInactive ? active : active & row.isActive.equals(true);
      })
      ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => OrderStatusConfig(
              id: row.id,
              name: row.name,
              colorValue: row.colorValue,
              isActive: row.isActive,
              sortOrder: row.sortOrder,
            ),
          )
          .toList(),
    );
  }

  @override
  Stream<List<OrderProductionItem>> watchItems(String orderId) =>
      (_db.select(_db.orderProductionItems)
            ..where(
              (row) => row.orderId.equals(orderId) & row.deletedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
          .watch()
          .map((rows) => rows.map(_mapItem).toList());

  @override
  Stream<List<OrderPayment>> watchPayments(String orderId) =>
      (_db.select(_db.orderPayments)
            ..where(
              (row) => row.orderId.equals(orderId) & row.deletedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.paidAt)]))
          .watch()
          .map((rows) => rows.map(_mapPayment).toList());

  @override
  Stream<List<OrderCostEntry>> watchCostEntries(String orderId) =>
      (_db.select(_db.orderCostEntries)
            ..where(
              (row) => row.orderId.equals(orderId) & row.deletedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.occurredAt)]))
          .watch()
          .map((rows) => rows.map(_mapCostEntry).toList());

  @override
  Stream<List<OrderFile>> watchFiles(String orderId) {
    final query = _db.select(_db.attachments)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            ((row.ownerType.equals('order') & row.ownerId.equals(orderId)) |
                (row.ownerType.equals('payment') &
                    row.ownerId.isInQuery(
                      _db.selectOnly(_db.orderPayments)
                        ..addColumns([_db.orderPayments.id])
                        ..where(
                          _db.orderPayments.orderId.equals(orderId) &
                              _db.orderPayments.deletedAt.isNull(),
                        ),
                    ))),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
    return query.watch().map(
      (rows) => rows.map((row) => _mapAttachmentFile(row, orderId)).toList(),
    );
  }

  @override
  Stream<List<OrderNote>> watchNotes(
    String orderId, {
    String search = '',
    int limit = 20,
    int offset = 0,
  }) {
    final term = search.trim();
    final query = _db.select(_db.orderNotes)
      ..where((row) {
        final active = row.orderId.equals(orderId) & row.deletedAt.isNull();
        return term.isEmpty ? active : active & row.content.like('%$term%');
      })
      ..orderBy([
        (row) => OrderingTerm.desc(row.createdAt),
        (row) => OrderingTerm.desc(row.sortOrder),
      ])
      ..limit(limit, offset: offset);
    return query.watch().map((rows) => rows.map(_mapNote).toList());
  }

  @override
  Stream<OrderNote?> watchLatestNote(String orderId) =>
      watchNotes(orderId, limit: 1).map((rows) => rows.firstOrNull);

  @override
  Stream<List<OrderTag>> watchOrderTags(String orderId) {
    final query =
        _db.select(_db.tags).join([
          innerJoin(
            _db.orderTagLinks,
            _db.orderTagLinks.tagId.equalsExp(_db.tags.id),
          ),
        ])..where(
          _db.orderTagLinks.orderId.equals(orderId) &
              _db.tags.deletedAt.isNull(),
        );
    return query.watch().map(
      (rows) =>
          rows.map((row) => row.readTable(_db.tags)).map(_mapTag).toList(),
    );
  }

  @override
  Stream<List<OrderTag>> watchAllTags({bool includeInactive = false}) =>
      (_db.select(_db.tags)
            ..where(
              (row) =>
                  row.scope.equals('order') &
                  (includeInactive
                      ? row.deletedAt.isNull()
                      : row.deletedAt.isNull() & row.isActive.equals(true)),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .watch()
          .map((rows) => rows.map(_mapTag).toList());

  @override
  Stream<List<OrderTag>> watchPopularTags({int limit = 8}) {
    final query =
        _db.select(_db.tags).join([
          leftOuterJoin(
            _db.orderTagLinks,
            _db.orderTagLinks.tagId.equalsExp(_db.tags.id),
          ),
          leftOuterJoin(
            _db.orders,
            _db.orders.id.equalsExp(_db.orderTagLinks.orderId) &
                _db.orders.deletedAt.isNull(),
          ),
        ])..where(
          _db.tags.scope.equals('order') &
              _db.tags.deletedAt.isNull() &
              _db.tags.isActive.equals(true),
        );
    return query.watch().map((rows) {
      final records = <String, TagRecord>{};
      final usage = <String, int>{};
      for (final row in rows) {
        final tag = row.readTable(_db.tags);
        records[tag.id] = tag;
        if (row.readTableOrNull(_db.orders) != null) {
          usage[tag.id] = (usage[tag.id] ?? 0) + 1;
        }
      }
      final sorted = records.values.toList()
        ..sort((left, right) {
          final byUsage = (usage[right.id] ?? 0).compareTo(usage[left.id] ?? 0);
          if (byUsage != 0) return byUsage;
          return left.createdAt.compareTo(right.createdAt);
        });
      return sorted.take(limit).map(_mapTag).toList();
    });
  }

  @override
  Stream<List<Factory>> watchFactories() =>
      (_db.select(_db.factories)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .watch()
          .map((rows) => rows.map(_mapFactory).toList());

  @override
  Stream<List<Product>> watchProducts() =>
      (_db.select(_db.products)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .watch()
          .map((rows) => rows.map(_mapProduct).toList());

  @override
  Future<SalesOrder> createOrder({
    required String customerId,
    String? orderNumber,
  }) async {
    final customer =
        await (_db.select(_db.customers)..where(
              (row) => row.id.equals(customerId) & row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (customer == null) {
      throw ArgumentError.value(customerId, 'customerId', '客户不存在');
    }
    final now = DateTime.now();
    final suffix = now.microsecondsSinceEpoch.toString();
    final generated = 'SO-${now.year}-${suffix.substring(suffix.length - 6)}';
    final order = SalesOrder(
      id: _uuid.v7(),
      orderNumber: orderNumber?.trim().isNotEmpty == true
          ? orderNumber!.trim()
          : generated,
      customerId: customerId,
      statusId: 'order-inquiry',
      priority: PriorityLevel.low,
      importance: false,
      urgency: false,
      currency: 'USD',
      baseProfitCurrency: 'CNY',
      exchangeRateMicros: 0,
      salesAmount: 0,
      taxRefund: 0,
      taxRefundCurrency: 'CNY',
      inlandCost: 0,
      portCharges: 0,
      otherCost: 0,
      otherIncome: 0,
      orderDate: DateTime(now.year, now.month, now.day),
      notes: '',
      sortOrder: now.microsecondsSinceEpoch,
      createdAt: now,
      updatedAt: now,
      version: 1,
    );
    await _db.into(_db.orders).insert(_toCompanion(order));
    return order;
  }

  @override
  Future<void> saveOrder(SalesOrder order) async {
    final current = await (_db.select(
      _db.orders,
    )..where((row) => row.id.equals(order.id))).getSingleOrNull();
    if (current == null) return;
    final next = order.copyWith(
      exchangeRateMicros: roundExchangeRateMicros(order.exchangeRateMicros),
      updatedAt: DateTime.now(),
      version: current.version + 1,
    );
    await (_db.update(
      _db.orders,
    )..where((row) => row.id.equals(order.id))).write(_toCompanion(next));
  }

  @override
  Future<void> setFinancialCurrency(String orderId, String currency) async {
    final normalized = currency.toUpperCase() == 'RMB'
        ? 'CNY'
        : currency.toUpperCase();
    if (normalized != 'CNY' && normalized != 'USD') {
      throw ArgumentError.value(currency, 'currency');
    }
    final now = DateTime.now();
    final current = await (_db.select(
      _db.orders,
    )..where((row) => row.id.equals(orderId))).getSingleOrNull();
    if (current == null) return;
    await (_db.update(
      _db.orders,
    )..where((row) => row.id.equals(orderId))).write(
      OrdersCompanion(
        currency: Value(normalized),
        baseProfitCurrency: const Value('CNY'),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ),
    );
  }

  @override
  Future<void> softDeleteOrder(String orderId) async {
    final links = await (_db.select(
      _db.orderTagLinks,
    )..where((row) => row.orderId.equals(orderId))).get();
    await (_db.update(
      _db.orders,
    )..where((row) => row.id.equals(orderId))).write(
      OrdersCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await collectUnusedTags(_db, links.map((link) => link.tagId));
  }

  @override
  Future<void> restoreOrder(String orderId) =>
      (_db.update(_db.orders)..where((row) => row.id.equals(orderId))).write(
        OrdersCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<OrderStatusConfig> createStatus(String name, {int? colorValue}) async {
    final now = DateTime.now();
    final status = OrderStatusConfig(
      id: _uuid.v7(),
      name: name.trim(),
      colorValue: colorValue ?? 0xFF667085,
      isActive: true,
      sortOrder: now.microsecondsSinceEpoch,
    );
    await _db
        .into(_db.orderStatuses)
        .insert(
          OrderStatusesCompanion.insert(
            id: status.id,
            name: status.name,
            colorValue: Value(status.colorValue),
            sortOrder: status.sortOrder,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return status;
  }

  @override
  Future<void> renameStatus(String statusId, String name) =>
      (_db.update(
        _db.orderStatuses,
      )..where((row) => row.id.equals(statusId))).write(
        OrderStatusesCompanion(
          name: Value(name.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> setStatusActive(String statusId, {required bool active}) =>
      (_db.update(
        _db.orderStatuses,
      )..where((row) => row.id.equals(statusId))).write(
        OrderStatusesCompanion(
          isActive: Value(active),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> setStatusColor(String statusId, int colorValue) =>
      (_db.update(
        _db.orderStatuses,
      )..where((row) => row.id.equals(statusId))).write(
        OrderStatusesCompanion(
          colorValue: Value(colorValue),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> reorderStatuses(List<String> orderedIds) =>
      _db.transaction(() async {
        for (var index = 0; index < orderedIds.length; index++) {
          await (_db.update(
            _db.orderStatuses,
          )..where((row) => row.id.equals(orderedIds[index]))).write(
            OrderStatusesCompanion(
              sortOrder: Value((index + 1) * 1024),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      });

  @override
  Future<OrderTag> findOrCreateTag(String name, {int? colorValue}) async {
    final trimmed = name.trim();
    final rows =
        await (_db.select(_db.tags)..where(
              (row) => row.scope.equals('order') & row.deletedAt.isNull(),
            ))
            .get();
    for (final row in rows) {
      if (row.name.toLowerCase() == trimmed.toLowerCase()) {
        if (!row.isActive) {
          await (_db.update(
            _db.tags,
          )..where((tag) => tag.id.equals(row.id))).write(
            TagsCompanion(
              isActive: const Value(true),
              updatedAt: Value(DateTime.now()),
            ),
          );
          return _mapTag(row).copyWith(isActive: true);
        }
        return _mapTag(row);
      }
    }
    final now = DateTime.now();
    final tag = OrderTag(
      id: _uuid.v7(),
      name: trimmed,
      colorValue: colorValue ?? 0xFFE9EFFB,
    );
    await _db
        .into(_db.tags)
        .insert(
          TagsCompanion.insert(
            id: tag.id,
            scope: const Value('order'),
            name: tag.name,
            colorValue: Value(tag.colorValue),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return tag;
  }

  @override
  Future<void> setOrderTags(String orderId, Iterable<String> tagIds) =>
      _db.transaction(() async {
        final previous = await (_db.select(
          _db.orderTagLinks,
        )..where((row) => row.orderId.equals(orderId))).get();
        final nextIds = tagIds.toSet();
        final scoped =
            await (_db.select(_db.tags)..where(
                  (r) =>
                      r.id.isIn(nextIds) &
                      r.scope.equals('order') &
                      r.deletedAt.isNull(),
                ))
                .get();
        if (scoped.length != nextIds.length) {
          throw ArgumentError('Order tags must belong to the order scope.');
        }
        await (_db.delete(
          _db.orderTagLinks,
        )..where((row) => row.orderId.equals(orderId))).go();
        for (final tagId in nextIds) {
          await _db
              .into(_db.orderTagLinks)
              .insert(
                OrderTagLinksCompanion.insert(orderId: orderId, tagId: tagId),
                mode: InsertMode.insertOrIgnore,
              );
        }
        await collectUnusedTags(
          _db,
          previous
              .map((link) => link.tagId)
              .where((id) => !nextIds.contains(id)),
        );
      });

  @override
  Future<void> renameTag(String tagId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await (_db.update(_db.tags)..where((row) => row.id.equals(tagId))).write(
      TagsCompanion(name: Value(trimmed), updatedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<void> setTagActive(String tagId, {required bool active}) =>
      (_db.update(_db.tags)..where((row) => row.id.equals(tagId))).write(
        TagsCompanion(
          isActive: Value(active),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> deleteTag(String tagId) =>
      TagCleanupService(_db).deleteTagDefinition(tagId);

  @override
  Future<Factory> findOrCreateFactory(String name, {int? colorValue}) async {
    final trimmed = name.trim();
    final existing =
        await (_db.select(_db.factories)..where(
              (row) => row.name.equals(trimmed) & row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) return _mapFactory(existing);
    final now = DateTime.now();
    final palette = [0xFFE9EFFB, 0xFFF8F1E4, 0xFFEAF4EF, 0xFFF0ECF8];
    final factory = Factory(
      id: _uuid.v7(),
      name: trimmed,
      contact: '',
      phone: '',
      address: '',
      note: '',
      colorValue: colorValue ?? palette[now.millisecond % palette.length],
    );
    await _db
        .into(_db.factories)
        .insert(
          FactoriesCompanion.insert(
            id: factory.id,
            name: factory.name,
            colorValue: Value(factory.colorValue),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return factory;
  }

  @override
  Future<Product> findOrCreateProduct(
    String name, {
    String unit = 'pcs',
  }) async {
    final trimmed = name.trim();
    final existing =
        await (_db.select(_db.products)..where(
              (row) => row.name.equals(trimmed) & row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) return _mapProduct(existing);
    final now = DateTime.now();
    final product = Product(
      id: _uuid.v7(),
      name: trimmed,
      unit: unit,
      note: '',
    );
    await _db
        .into(_db.products)
        .insert(
          ProductsCompanion.insert(
            id: product.id,
            name: product.name,
            unit: Value(product.unit),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return product;
  }

  @override
  Future<OrderProductionItem> addProductionItem(
    String orderId, {
    required String factoryName,
    required String productName,
    int quantityMilli = 1000,
    String unit = 'pcs',
    int unitPrice = 0,
    int salesAmount = 0,
    int factoryCost = 0,
    String factoryCostCurrency = 'CNY',
  }) async {
    if (factoryName.trim().isEmpty) {
      throw ArgumentError.value(factoryName, 'factoryName');
    }
    if (productName.trim().isEmpty) {
      throw ArgumentError.value(productName, 'productName');
    }
    if (quantityMilli <= 0) {
      throw ArgumentError.value(quantityMilli, 'quantityMilli');
    }
    final factory = await findOrCreateFactory(factoryName);
    final product = await findOrCreateProduct(productName, unit: unit);
    final now = DateTime.now();
    final item = OrderProductionItem(
      id: _uuid.v7(),
      orderId: orderId,
      factoryId: factory.id,
      productId: product.id,
      quantityMilli: quantityMilli,
      unit: unit,
      unitPrice: unitPrice,
      salesAmount: salesAmount,
      factoryCost: factoryCost,
      factoryCostCurrency: factoryCostCurrency,
      productionStatus: 'pending',
      factoryOrderStatus: FactoryOrderStatus.notPlaced,
      colorValue: factory.colorValue,
      note: '',
      sortOrder: now.microsecondsSinceEpoch,
    );
    await _db
        .into(_db.orderProductionItems)
        .insert(
          OrderProductionItemsCompanion.insert(
            id: item.id,
            orderId: orderId,
            factoryId: Value(item.factoryId),
            productId: Value(item.productId),
            quantityMilli: Value(quantityMilli),
            unit: Value(unit),
            unitPrice: Value(unitPrice),
            salesAmount: Value(salesAmount),
            factoryCost: Value(factoryCost),
            factoryCostCurrency: Value(factoryCostCurrency),
            productionStatus: Value(item.productionStatus),
            factoryOrderStatus: Value(item.factoryOrderStatus.name),
            colorValue: Value(item.colorValue),
            note: Value(item.note),
            sortOrder: item.sortOrder,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return item;
  }

  @override
  Future<void> saveProductionItem(
    OrderProductionItem item, {
    required String factoryName,
    required String productName,
  }) async {
    if (factoryName.trim().isEmpty || productName.trim().isEmpty) {
      throw ArgumentError('工厂和产品不能为空');
    }
    if (item.quantityMilli <= 0) {
      throw ArgumentError.value(item.quantityMilli, 'quantityMilli');
    }
    final factory = await findOrCreateFactory(factoryName.trim());
    final product = await findOrCreateProduct(
      productName.trim(),
      unit: item.unit,
    );
    await (_db.update(
      _db.orderProductionItems,
    )..where((row) => row.id.equals(item.id))).write(
      OrderProductionItemsCompanion(
        factoryId: Value(factory.id),
        productId: Value(product.id),
        quantityMilli: Value(item.quantityMilli),
        unit: Value(item.unit),
        unitPrice: Value(item.unitPrice),
        salesAmount: Value(item.salesAmount),
        factoryCost: Value(item.factoryCost),
        factoryCostCurrency: Value(item.factoryCostCurrency),
        productionStatus: Value(item.productionStatus),
        factoryOrderStatus: Value(item.factoryOrderStatus.name),
        colorValue: Value(factory.colorValue),
        note: Value(item.note),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> updateFactoryOrderStatus(
    String itemId,
    FactoryOrderStatus status,
  ) =>
      (_db.update(
        _db.orderProductionItems,
      )..where((row) => row.id.equals(itemId))).write(
        OrderProductionItemsCompanion(
          factoryOrderStatus: Value(status.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> removeProductionItem(String itemId) =>
      (_db.update(
        _db.orderProductionItems,
      )..where((row) => row.id.equals(itemId))).write(
        OrderProductionItemsCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<OrderNote> addNote(String orderId, {required String content}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(content, 'content');
    final existing =
        await (_db.select(_db.orderNotes)..where(
              (row) => row.orderId.equals(orderId) & row.deletedAt.isNull(),
            ))
            .get();
    const colors = [0xFFE9EFFB, 0xFFF8F1E4, 0xFFEAF4EF, 0xFFF0ECF8, 0xFFF2F3F5];
    final now = DateTime.now();
    final note = OrderNote(
      id: _uuid.v7(),
      orderId: orderId,
      content: trimmed,
      createdAt: now,
      updatedAt: now,
      colorValue: colors[existing.length % colors.length],
      sortOrder: now.microsecondsSinceEpoch,
      version: 1,
    );
    await _db
        .into(_db.orderNotes)
        .insert(
          OrderNotesCompanion.insert(
            id: note.id,
            orderId: orderId,
            content: Value(note.content),
            colorValue: Value(note.colorValue),
            sortOrder: Value(note.sortOrder),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return note;
  }

  @override
  Future<void> saveNote(OrderNote note) async {
    final now = DateTime.now();
    await (_db.update(
      _db.orderNotes,
    )..where((row) => row.id.equals(note.id))).write(
      OrderNotesCompanion(
        content: Value(note.content.trim()),
        colorValue: Value(note.colorValue),
        sortOrder: Value(note.sortOrder),
        updatedAt: Value(now),
        version: Value(note.version + 1),
      ),
    );
  }

  @override
  Future<void> softDeleteNote(String noteId) =>
      (_db.update(_db.orderNotes)..where((row) => row.id.equals(noteId))).write(
        OrderNotesCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<OrderPayment> addPayment(
    String orderId, {
    required int amount,
    required String currency,
    required String paymentType,
    required DateTime paidAt,
    String method = '',
    String note = '',
    String? attachmentId,
  }) async {
    final now = DateTime.now();
    final payment = OrderPayment(
      id: _uuid.v7(),
      orderId: orderId,
      amount: amount,
      currency: currency,
      paymentType: paymentType,
      paidAt: paidAt,
      method: method,
      note: note,
      attachmentId: attachmentId,
      createdAt: now,
      updatedAt: now,
    );
    await _db
        .into(_db.orderPayments)
        .insert(
          OrderPaymentsCompanion.insert(
            id: payment.id,
            orderId: orderId,
            amount: amount,
            currency: Value(currency),
            paymentType: Value(paymentType.trim()),
            paidAt: paidAt,
            method: Value(method),
            note: Value(note),
            attachmentId: Value(attachmentId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return payment;
  }

  @override
  Future<void> savePayment(OrderPayment payment) =>
      (_db.update(
        _db.orderPayments,
      )..where((row) => row.id.equals(payment.id))).write(
        OrderPaymentsCompanion(
          amount: Value(payment.amount),
          currency: Value(payment.currency),
          paymentType: Value(payment.paymentType.trim()),
          paidAt: Value(payment.paidAt),
          attachmentId: Value(payment.attachmentId),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> removePayment(String paymentId) =>
      (_db.update(
        _db.orderPayments,
      )..where((row) => row.id.equals(paymentId))).write(
        OrderPaymentsCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<OrderCostEntry> addCostEntry(
    String orderId, {
    required int amountMinor,
    required String currency,
    required String costType,
    required DateTime occurredAt,
    String? attachmentId,
  }) async {
    final now = DateTime.now();
    final entry = OrderCostEntry(
      id: _uuid.v7(),
      orderId: orderId,
      amountMinor: amountMinor,
      currency: currency,
      costType: costType.trim(),
      occurredAt: occurredAt,
      attachmentId: attachmentId,
      createdAt: now,
      updatedAt: now,
    );
    await _db
        .into(_db.orderCostEntries)
        .insert(
          OrderCostEntriesCompanion.insert(
            id: entry.id,
            orderId: orderId,
            amountMinor: amountMinor,
            currency: Value(currency),
            costType: Value(entry.costType),
            occurredAt: occurredAt,
            attachmentId: Value(attachmentId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return entry;
  }

  @override
  Future<void> saveCostEntry(OrderCostEntry entry) =>
      (_db.update(
        _db.orderCostEntries,
      )..where((row) => row.id.equals(entry.id))).write(
        OrderCostEntriesCompanion(
          amountMinor: Value(entry.amountMinor),
          currency: Value(entry.currency),
          costType: Value(entry.costType.trim()),
          occurredAt: Value(entry.occurredAt),
          attachmentId: Value(entry.attachmentId),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> removeCostEntry(String entryId) =>
      (_db.update(
        _db.orderCostEntries,
      )..where((row) => row.id.equals(entryId))).write(
        OrderCostEntriesCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<OrderFile> addFileMetadata({
    required String orderId,
    String? paymentId,
    required String fileName,
    required String originalName,
    required OrderDocumentType documentType,
    required String localRelativePath,
    required int fileSize,
    required String mimeType,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v7();
    final file = OrderFile(
      id: id,
      orderId: orderId,
      paymentId: paymentId,
      fileName: fileName,
      originalName: originalName,
      documentType: documentType,
      localRelativePath: localRelativePath,
      fileSize: fileSize,
      mimeType: mimeType,
      createdAt: now,
    );
    await _db
        .into(_db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: id,
            ownerType: paymentId == null ? 'order' : 'payment',
            ownerId: paymentId ?? orderId,
            fileName: fileName,
            originalName: originalName,
            documentType: Value(documentType.name),
            relativePath: localRelativePath,
            fileSize: fileSize,
            mimeType: Value(mimeType),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return file;
  }

  @override
  Future<void> changeFileDocumentType(
    String fileId,
    OrderDocumentType documentType,
  ) => (_db.update(_db.attachments)..where((row) => row.id.equals(fileId)))
      .write(
        AttachmentsCompanion(
          documentType: Value(documentType.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> removeFile(String fileId) =>
      (_db.update(
        _db.attachments,
      )..where((row) => row.id.equals(fileId))).write(
        AttachmentsCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  SalesOrder _mapOrder(OrderRecord row) => SalesOrder(
    id: row.id,
    orderNumber: row.orderNumber,
    customerId: row.customerId,
    statusId: row.statusId,
    priority: PriorityLevel.values.firstWhere(
      (value) => value.name == row.priority,
      orElse: () => PriorityLevel.low,
    ),
    importance: row.importance,
    urgency: row.urgency,
    currency: row.currency,
    baseProfitCurrency: row.baseProfitCurrency,
    exchangeRateMicros: row.exchangeRateMicros,
    salesAmount: row.salesAmount,
    taxRefund: row.taxRefund,
    taxRefundCurrency: row.taxRefundCurrency,
    inlandCost: row.inlandCost,
    portCharges: row.portCharges,
    otherCost: row.otherCost,
    otherIncome: row.otherIncome,
    orderDate: row.orderDate,
    deliveryDate: row.deliveryDate,
    notes: row.notes,
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    version: row.version,
  );

  OrdersCompanion _toCompanion(SalesOrder value) => OrdersCompanion(
    id: Value(value.id),
    orderNumber: Value(value.orderNumber),
    customerId: Value(value.customerId),
    statusId: Value(value.statusId),
    priority: Value(value.priority.name),
    importance: Value(value.importance),
    urgency: Value(value.urgency),
    currency: Value(value.currency),
    baseProfitCurrency: Value(value.baseProfitCurrency),
    exchangeRateMicros: Value(value.exchangeRateMicros),
    salesAmount: Value(value.salesAmount),
    taxRefund: Value(value.taxRefund),
    taxRefundCurrency: Value(value.taxRefundCurrency),
    inlandCost: Value(value.inlandCost),
    portCharges: Value(value.portCharges),
    otherCost: Value(value.otherCost),
    otherIncome: Value(value.otherIncome),
    orderDate: Value(value.orderDate),
    deliveryDate: Value(value.deliveryDate),
    notes: Value(value.notes),
    sortOrder: Value(value.sortOrder),
    createdAt: Value(value.createdAt),
    updatedAt: Value(value.updatedAt),
    deletedAt: Value(value.deletedAt),
    version: Value(value.version),
  );

  OrderProductionItem _mapItem(OrderProductionItemRecord row) =>
      OrderProductionItem(
        id: row.id,
        orderId: row.orderId,
        factoryId: row.factoryId,
        productId: row.productId,
        quantityMilli: row.quantityMilli,
        unit: row.unit,
        unitPrice: row.unitPrice,
        salesAmount: row.salesAmount,
        factoryCost: row.factoryCost,
        factoryCostCurrency: row.factoryCostCurrency,
        productionStatus: row.productionStatus,
        factoryOrderStatus: FactoryOrderStatus.values.firstWhere(
          (value) => value.name == row.factoryOrderStatus,
          orElse: () => FactoryOrderStatus.notPlaced,
        ),
        colorValue: row.colorValue,
        note: row.note,
        sortOrder: row.sortOrder,
      );

  OrderPayment _mapPayment(OrderPaymentRecord row) => OrderPayment(
    id: row.id,
    orderId: row.orderId,
    amount: row.amount,
    currency: row.currency,
    paymentType: row.paymentType,
    paidAt: row.paidAt,
    method: row.method,
    note: row.note,
    attachmentId: row.attachmentId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  OrderCostEntry _mapCostEntry(OrderCostEntryRecord row) => OrderCostEntry(
    id: row.id,
    orderId: row.orderId,
    amountMinor: row.amountMinor,
    currency: row.currency,
    costType: row.costType,
    occurredAt: row.occurredAt,
    attachmentId: row.attachmentId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  OrderFile _mapAttachmentFile(AttachmentRecord row, String orderId) =>
      OrderFile(
        id: row.id,
        orderId: orderId,
        paymentId: row.ownerType == 'payment' ? row.ownerId : null,
        fileName: row.fileName,
        originalName: row.originalName,
        documentType: OrderDocumentType.values.firstWhere(
          (value) => value.name == row.documentType,
          orElse: () => OrderDocumentType.other,
        ),
        localRelativePath: row.relativePath,
        fileSize: row.fileSize,
        mimeType: row.mimeType,
        createdAt: row.createdAt,
      );

  OrderNote _mapNote(OrderNoteRecord row) => OrderNote(
    id: row.id,
    orderId: row.orderId,
    content: row.content,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    colorValue: row.colorValue,
    sortOrder: row.sortOrder,
    deletedAt: row.deletedAt,
    version: row.version,
  );

  OrderTag _mapTag(TagRecord row) => OrderTag(
    id: row.id,
    name: row.name,
    colorValue: row.colorValue,
    isActive: row.isActive,
  );

  Factory _mapFactory(FactoryRecord row) => Factory(
    id: row.id,
    name: row.name,
    contact: row.contact,
    phone: row.phone,
    address: row.address,
    note: row.note,
    colorValue: row.colorValue,
  );

  Product _mapProduct(ProductRecord row) =>
      Product(id: row.id, name: row.name, unit: row.unit, note: row.note);

  Comparator<SalesOrder> _orderComparator(
    OrderSort sort, {
    required Map<String, String> customerNames,
    required Map<String, int> factoryCosts,
  }) {
    int compareDate(DateTime? left, DateTime? right) {
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    }

    int profit(SalesOrder order) {
      final sales =
          order.currency.toUpperCase() == order.baseProfitCurrency.toUpperCase()
          ? order.salesAmount
          : order.exchangeRateMicros <= 0
          ? null
          : (order.salesAmount * order.exchangeRateMicros / 1000000).round();
      if (sales == null) return -0x7FFFFFFFFFFFFFFF;
      return sales -
          (factoryCosts[order.id] ?? 0) -
          order.inlandCost -
          order.portCharges -
          order.otherCost +
          order.taxRefund +
          order.otherIncome;
    }

    return (left, right) => switch (sort) {
      OrderSort.createdAt =>
        orderDisplayRank(left).compareTo(orderDisplayRank(right)) != 0
            ? orderDisplayRank(left).compareTo(orderDisplayRank(right))
            : right.createdAt.compareTo(left.createdAt) != 0
            ? right.createdAt.compareTo(left.createdAt)
            : right.sortOrder.compareTo(left.sortOrder),
      OrderSort.manual => left.sortOrder.compareTo(right.sortOrder),
      OrderSort.orderDate => compareDate(right.orderDate, left.orderDate),
      OrderSort.deliveryDate => compareDate(
        left.deliveryDate,
        right.deliveryDate,
      ),
      OrderSort.priority => right.priority.index.compareTo(left.priority.index),
      OrderSort.status => (left.statusId ?? '').compareTo(right.statusId ?? ''),
      OrderSort.customer => (customerNames[left.id] ?? '').compareTo(
        customerNames[right.id] ?? '',
      ),
      OrderSort.amount => right.salesAmount.compareTo(left.salesAmount),
      OrderSort.profit => profit(right).compareTo(profit(left)),
    };
  }
}
