import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:excel/excel.dart';

import '../../core/database/app_database.dart';

class FlyExcelExportService {
  const FlyExcelExportService(this.database);

  final AppDatabase database;

  Future<Uint8List> buildWorkbook({
    Set<String>? customerIds,
    Set<String>? orderIds,
    String Function(String)? translate,
  }) async {
    String copy(String value) => translate?.call(value) ?? value;
    void header(Sheet sheet, List<String> values) =>
        _header(sheet, values.map(copy).toList());
    final customers = await (database.select(
      database.customers,
    )..where((row) => row.deletedAt.isNull())).get();
    final orders = await (database.select(
      database.orders,
    )..where((row) => row.deletedAt.isNull())).get();
    var customerScope = customerIds == null ? null : {...customerIds};
    var orderScope = orderIds == null ? null : {...orderIds};
    if (customerScope != null && orderScope == null) {
      orderScope ??= {
        for (final order in orders)
          if (order.customerId != null &&
              customerScope.contains(order.customerId))
            order.id,
      };
    }
    if (orderScope != null && customerScope == null) {
      customerScope ??= {
        for (final order in orders)
          if (orderScope.contains(order.id) && order.customerId != null)
            order.customerId!,
      };
    }
    final scopedCustomers = customers
        .where((row) => customerScope == null || customerScope.contains(row.id))
        .toList();
    final scopedOrders = orders
        .where((row) => orderScope == null || orderScope.contains(row.id))
        .toList();
    final scopedOrderIds = scopedOrders.map((row) => row.id).toSet();

    final customerStatuses = {
      for (final row in await database.select(database.customerStatuses).get())
        row.id: row.name,
    };
    final sources = {
      for (final row in await database.select(database.customerSources).get())
        row.id: row.name,
    };
    final orderStatuses = {
      for (final row in await database.select(database.orderStatuses).get())
        row.id: row.name,
    };
    final factories = {
      for (final row in await database.select(database.factories).get())
        row.id: row.name,
    };
    final products = {
      for (final row in await database.select(database.products).get())
        row.id: row.name,
    };
    final tags = {
      for (final row in await database.select(database.tags).get())
        row.id: row.name,
    };
    final customerTagLinks = await database
        .select(database.customerTagLinks)
        .get();
    final orderTagLinks = await database.select(database.orderTagLinks).get();
    final followUps =
        await (database.select(database.customerFollowUps)
              ..where((row) => row.deletedAt.isNull())
              ..orderBy([(row) => OrderingTerm.desc(row.followedUpAt)]))
            .get();

    final book = Excel.createExcel();
    final defaultName = book.getDefaultSheet();
    if (defaultName != null) book.rename(defaultName, 'Customers');
    final customerSheet = book['Customers'];
    header(customerSheet, const [
      'Customer ID',
      '客户名称',
      '公司名称',
      '国家',
      '城市',
      '来源',
      '状态',
      '优先级',
      '标签',
      'Email',
      'WhatsApp',
      'Phone',
      '下次跟进',
      '上次跟进',
      '最近跟进内容',
      '备注',
      '创建日期',
    ]);
    for (final row in scopedCustomers) {
      final latest = followUps
          .where((item) => item.customerId == row.id)
          .firstOrNull;
      final tagText = customerTagLinks
          .where((link) => link.customerId == row.id)
          .map((link) => tags[link.tagId])
          .whereType<String>()
          .join(', ');
      customerSheet.appendRow([
        _text(row.id),
        _text(row.name),
        _text(row.companyName),
        _text(row.country),
        _text(row.city),
        _text(sources[row.sourceId] ?? ''),
        _text(customerStatuses[row.statusId] ?? ''),
        _text(row.priority),
        _text(tagText),
        _text(row.email),
        _text(row.whatsapp),
        _text(row.phone),
        _date(row.nextFollowUpDate),
        _date(row.lastFollowUpAt),
        _text(latest?.content ?? ''),
        _text(row.notes),
        _date(row.createdAt),
      ]);
    }

    final orderSheet = book['Orders'];
    header(orderSheet, const [
      'Order ID',
      '订单号',
      'Customer ID',
      '客户名称',
      '状态',
      '级别',
      '标签',
      '订单日期',
      '预计交期',
      '销售金额',
      '销售币种',
      'USD→RMB汇率',
      '退税金额',
      '退税币种',
      '创建日期',
    ]);
    final customerNames = {for (final row in customers) row.id: row.name};
    for (final row in scopedOrders) {
      final level = row.urgency
          ? '紧急'
          : row.importance
          ? '重要'
          : '一般';
      final tagText = orderTagLinks
          .where((link) => link.orderId == row.id)
          .map((link) => tags[link.tagId])
          .whereType<String>()
          .join(', ');
      orderSheet.appendRow([
        _text(row.id),
        _text(row.orderNumber),
        _text(row.customerId ?? ''),
        _text(customerNames[row.customerId] ?? ''),
        _text(orderStatuses[row.statusId] ?? ''),
        _text(copy(level)),
        _text(tagText),
        _date(row.orderDate),
        _date(row.deliveryDate),
        DoubleCellValue(row.salesAmount / 100),
        _text(_currency(row.currency)),
        row.exchangeRateMicros <= 0
            ? null
            : DoubleCellValue(
                ((row.exchangeRateMicros / 10000).round() * 10000) / 1000000,
              ),
        DoubleCellValue(row.taxRefund / 100),
        _text(_currency(row.taxRefundCurrency)),
        _date(row.createdAt),
      ]);
    }

    final itemSheet = book['OrderItems'];
    header(itemSheet, const [
      'Item ID',
      'Order ID',
      'Factory ID',
      '工厂',
      'Product ID',
      '产品',
      '数量',
      '单位',
      '成本',
      '成本币种',
      '工厂下单状态',
      '生产状态',
    ]);
    final items = await (database.select(
      database.orderProductionItems,
    )..where((row) => row.deletedAt.isNull())).get();
    for (final row in items.where(
      (row) => scopedOrderIds.contains(row.orderId),
    )) {
      itemSheet.appendRow([
        _text(row.id),
        _text(row.orderId),
        _text(row.factoryId ?? ''),
        _text(factories[row.factoryId] ?? ''),
        _text(row.productId ?? ''),
        _text(products[row.productId] ?? ''),
        DoubleCellValue(row.quantityMilli / 1000),
        _text(row.unit),
        DoubleCellValue(row.factoryCost / 100),
        _text(_currency(row.factoryCostCurrency)),
        _text(row.factoryOrderStatus),
        _text(row.productionStatus),
      ]);
    }

    final paymentSheet = book['Payments'];
    header(paymentSheet, const [
      'Payment ID',
      'Order ID',
      '金额',
      '币种',
      '类型',
      '收款日期',
      '方式',
      '备注',
    ]);
    final payments = await (database.select(
      database.orderPayments,
    )..where((row) => row.deletedAt.isNull())).get();
    for (final row in payments.where(
      (row) => scopedOrderIds.contains(row.orderId),
    )) {
      paymentSheet.appendRow([
        _text(row.id),
        _text(row.orderId),
        DoubleCellValue(row.amount / 100),
        _text(_currency(row.currency)),
        _text(row.paymentType),
        _date(row.paidAt),
        _text(row.method),
        _text(row.note),
      ]);
    }

    final costSheet = book['Costs'];
    header(costSheet, const ['Cost ID', 'Order ID', '金额', '币种', '类型', '发生日期']);
    final costs = await (database.select(
      database.orderCostEntries,
    )..where((row) => row.deletedAt.isNull())).get();
    for (final row in costs.where(
      (row) => scopedOrderIds.contains(row.orderId),
    )) {
      costSheet.appendRow([
        _text(row.id),
        _text(row.orderId),
        DoubleCellValue(row.amountMinor / 100),
        _text(_currency(row.currency)),
        _text(row.costType),
        _date(row.occurredAt),
      ]);
    }

    for (final name in [
      'Customers',
      'Orders',
      'OrderItems',
      'Payments',
      'Costs',
    ]) {
      final sheet = book[name];
      for (var column = 0; column < sheet.maxColumns; column++) {
        sheet.setColumnWidth(column, column == 0 || column == 1 ? 23 : 16);
      }
    }
    final encoded = book.encode();
    if (encoded == null) throw StateError(copy('Excel 文件生成失败'));
    return Uint8List.fromList(_freezeHeaderRows(encoded));
  }

  static void _header(Sheet sheet, List<String> values) {
    sheet.appendRow(values.map(_text).toList());
    for (var index = 0; index < values.length; index++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: index, rowIndex: 0))
          .cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#E8EFE4'),
      );
    }
  }

  static TextCellValue _text(String value) => TextCellValue(value);
  static CellValue? _date(DateTime? value) => value == null
      ? null
      : TextCellValue(
          '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
        );
  static String _currency(String value) =>
      value.toUpperCase() == 'RMB' || value.toUpperCase() == 'CNY'
      ? 'RMB'
      : 'USD';

  static List<int> _freezeHeaderRows(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final output = Archive();
    for (final file in archive.files) {
      var data = file.content as List<int>;
      if (file.name.startsWith('xl/worksheets/sheet') &&
          file.name.endsWith('.xml')) {
        var xml = String.fromCharCodes(data);
        xml = xml.replaceFirstMapped(
          RegExp(r'<sheetView([^>]*)/>'),
          (match) =>
              '<sheetView${match.group(1)}><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView>',
        );
        data = Uint8List.fromList(xml.codeUnits);
      }
      output.addFile(ArchiveFile(file.name, data.length, data));
    }
    return ZipEncoder().encode(output)!;
  }
}
