import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../features/orders/domain/order.dart';
import '../../../shared/domain/priority.dart';
import '../domain/dashboard_snapshot.dart';
import '../../tasks/data/task_date_query.dart';

class DashboardService {
  DashboardService(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  Stream<DashboardSnapshot> watch() => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.customers,
          _db.tasks,
          _db.orders,
          _db.orderProductionItems,
          _db.orderPayments,
          _db.orderCostEntries,
        },
      )
      .watch()
      .asyncMap((_) => load());

  Future<DashboardSnapshot> load() async {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final monthEnd = DateTime(now.year, now.month + 1);

    final customerRows =
        await (_db.select(_db.customers)
              ..where(
                (row) =>
                    row.deletedAt.isNull() &
                    row.nextFollowUpDate.isSmallerThanValue(tomorrow) &
                    (row.lastFollowUpAt.isNull() |
                        row.lastFollowUpAt.isSmallerThanValue(today)),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.nextFollowUpDate)]))
            .get();
    final customerNames = {
      for (final row in await (_db.select(
        _db.customers,
      )..where((row) => row.deletedAt.isNull())).get())
        row.id: row.name,
    };

    final taskRows =
        await (_db.select(_db.tasks)
              ..where((row) => taskTodayPredicate(row, now))
              ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
            .get();
    final importantUrgentRows =
        await (_db.select(_db.tasks)
              ..where(
                (row) =>
                    row.deletedAt.isNull() &
                    row.status.equals('open') &
                    row.importance.equals(true) &
                    row.urgency.equals(true),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.dueDate),
                (row) => OrderingTerm.asc(row.sortOrder),
              ]))
            .get();

    final orderRows = await (_db.select(
      _db.orders,
    )..where((row) => row.deletedAt.isNull())).get();
    final itemRows = await (_db.select(
      _db.orderProductionItems,
    )..where((row) => row.deletedAt.isNull())).get();
    final paymentRows = await (_db.select(
      _db.orderPayments,
    )..where((row) => row.deletedAt.isNull())).get();
    final costRows = await (_db.select(
      _db.orderCostEntries,
    )..where((row) => row.deletedAt.isNull())).get();

    final items = <String, List<OrderProductionItem>>{};
    for (final row in itemRows) {
      items.putIfAbsent(row.orderId, () => []).add(_mapItem(row));
    }
    final payments = <String, List<OrderPayment>>{};
    for (final row in paymentRows) {
      payments.putIfAbsent(row.orderId, () => []).add(_mapPayment(row));
    }
    final costs = <String, List<OrderCostEntry>>{};
    for (final row in costRows) {
      costs.putIfAbsent(row.orderId, () => []).add(_mapCost(row));
    }

    final outstanding = <DashboardEntry>[];
    final outstandingByCurrency = <String, int>{};
    final urgent = <DashboardEntry>[];
    var monthProfit = 0;
    var monthMissingRate = 0;
    for (final row in orderRows) {
      final order = _mapOrder(row);
      final summary = OrderFinancialSummary(
        order: order,
        items: items[order.id] ?? const [],
        payments: payments[order.id] ?? const [],
        costEntries: costs[order.id] ?? const [],
      );
      final outstandingAmount = summary.outstandingAmount;
      if (outstandingAmount != null && outstandingAmount > 0) {
        final currency = OrderFinancialSummary.normalizeCurrency(
          order.currency,
        );
        outstandingByCurrency[currency] =
            (outstandingByCurrency[currency] ?? 0) + outstandingAmount;
        outstanding.add(
          DashboardEntry(
            id: order.id,
            title: order.orderNumber,
            subtitle: customerNames[order.customerId] ?? '',
          ),
        );
      }
      if (order.urgency) {
        urgent.add(
          DashboardEntry(
            id: order.id,
            title: order.orderNumber,
            subtitle: customerNames[order.customerId] ?? '',
          ),
        );
      }
      final date = order.orderDate ?? order.createdAt;
      if (!date.isBefore(today.copyWith(day: 1)) && date.isBefore(monthEnd)) {
        final profit = summary.profit;
        if (profit == null) {
          monthMissingRate += 1;
        } else {
          monthProfit += profit;
        }
      }
    }

    urgent.sort((a, b) => a.title.compareTo(b.title));
    final taskExists =
        await (_db.select(_db.tasks)
              ..where((r) => r.deletedAt.isNull())
              ..limit(1))
            .get();
    return DashboardSnapshot(
      hasBusinessData:
          customerNames.isNotEmpty ||
          orderRows.isNotEmpty ||
          taskExists.isNotEmpty,
      todayCustomers: customerRows
          .map(
            (row) => DashboardEntry(
              id: row.id,
              title: row.name,
              subtitle: row.nextActionType ?? row.nextAction,
            ),
          )
          .toList(),
      todayTasks: taskRows
          .map((row) => DashboardEntry(id: row.id, title: row.title))
          .toList(),
      importantUrgentTasks: importantUrgentRows
          .map((row) => DashboardEntry(id: row.id, title: row.title))
          .toList(),
      outstandingOrders: outstanding,
      outstandingByCurrency: outstandingByCurrency,
      urgentOrders: urgent,
      monthProfitRmb: monthProfit,
      monthMissingRateCount: monthMissingRate,
    );
  }

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

  OrderCostEntry _mapCost(OrderCostEntryRecord row) => OrderCostEntry(
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
}
