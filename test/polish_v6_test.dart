import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/domain/order.dart';
import 'package:fly/shared/design_system/fly_color_scheme.dart';
import 'package:fly/shared/export/fly_excel_export_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftCustomerRepository customers;
  late DriftOrderRepository orders;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.ensureBuiltInData();
    customers = DriftCustomerRepository(database);
    orders = DriftOrderRepository(database);
  });

  tearDown(() => database.close());

  test(
    'V6 financials convert each currency and always report RMB profit',
    () async {
      final customer = await customers.createCustomer(name: 'FX Customer');
      final created = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-V6-FX',
      );
      final order = created.copyWith(
        currency: 'USD',
        baseProfitCurrency: 'CNY',
        exchangeRateMicros: 7000000,
        salesAmount: 2000000,
        taxRefund: 150000,
        taxRefundCurrency: 'CNY',
      );
      await orders.saveOrder(order);
      await orders.addProductionItem(
        order.id,
        factoryName: 'Factory',
        productName: 'WPC',
        factoryCost: 9000000,
        factoryCostCurrency: 'CNY',
      );
      await orders.addCostEntry(
        order.id,
        amountMinor: 500000,
        currency: 'CNY',
        costType: '内陆费',
        occurredAt: DateTime(2026, 9, 4),
      );
      await orders.addPayment(
        order.id,
        amount: 500000,
        currency: 'USD',
        paymentType: '定金',
        paidAt: DateTime(2026, 9, 4),
      );
      await orders.addPayment(
        order.id,
        amount: 700000,
        currency: 'CNY',
        paymentType: '补款',
        paidAt: DateTime(2026, 9, 4),
      );
      final summary = OrderFinancialSummary(
        order: order,
        items: await orders.watchItems(order.id).first,
        payments: await orders.watchPayments(order.id).first,
        costEntries: await orders.watchCostEntries(order.id).first,
      );
      expect(summary.salesRmb, 14000000);
      expect(summary.receivedRmb, 4200000);
      expect(summary.totalCostRmb, 9500000);
      expect(summary.profit, 4650000);
      expect(summary.currency, 'CNY');
      expect(summary.receivedByCurrency, {'USD': 500000, 'CNY': 700000});
    },
  );

  test(
    'mixed-currency profit and outstanding wait for a missing rate',
    () async {
      final customer = await customers.createCustomer(name: 'No Rate');
      final created = await orders.createOrder(customerId: customer.id);
      final order = created.copyWith(
        salesAmount: 2000000,
        exchangeRateMicros: 0,
      );
      await orders.addPayment(
        order.id,
        amount: 500000,
        currency: 'CNY',
        paymentType: '定金',
        paidAt: DateTime(2026, 9, 4),
      );
      final summary = OrderFinancialSummary(
        order: order,
        items: const [],
        payments: await orders.watchPayments(order.id).first,
      );
      expect(summary.profit, isNull);
      expect(summary.receivedRmb, 500000);
      expect(summary.outstandingAmount, isNull);
    },
  );

  test(
    'order production item can edit identity quantity cost and currency',
    () async {
      final customer = await customers.createCustomer(name: 'Item Edit');
      final order = await orders.createOrder(customerId: customer.id);
      final item = await orders.addProductionItem(
        order.id,
        factoryName: 'Factory A',
        productName: 'Panel A',
      );
      await orders.saveProductionItem(
        item.copyWith(
          quantityMilli: 12500,
          unit: '㎡',
          factoryCost: 880000,
          factoryCostCurrency: 'USD',
        ),
        factoryName: 'Factory B',
        productName: 'Panel B',
      );
      final saved = (await orders.watchItems(order.id).first).single;
      final factories = await orders.watchFactories().first;
      final products = await orders.watchProducts().first;
      expect(saved.quantityMilli, 12500);
      expect(saved.factoryCost, 880000);
      expect(saved.factoryCostCurrency, 'USD');
      expect(
        factories.firstWhere((row) => row.id == saved.factoryId).name,
        'Factory B',
      );
      expect(
        products.firstWhere((row) => row.id == saved.productId).name,
        'Panel B',
      );
    },
  );

  test(
    'Excel export preserves cross-sheet IDs and freezes header rows',
    () async {
      final customer = await customers.createCustomer(name: 'Excel Customer');
      final order = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-EXCEL',
      );
      final item = await orders.addProductionItem(
        order.id,
        factoryName: 'Excel Factory',
        productName: 'Excel Product',
        factoryCost: 123400,
      );
      final payment = await orders.addPayment(
        order.id,
        amount: 50000,
        currency: 'USD',
        paymentType: '定金',
        paidAt: DateTime(2026, 9, 4),
      );
      final bytes = await FlyExcelExportService(database)
          .buildWorkbook(orderIds: {order.id});
      final workbook = Excel.decodeBytes(bytes);
      expect(
        workbook.tables.keys,
        containsAll(['Customers', 'Orders', 'OrderItems', 'Payments', 'Costs']),
      );
      String value(String sheet, int row, int column) =>
          workbook.tables[sheet]!.rows[row][column]!.value.toString();
      expect(value('Customers', 1, 0), customer.id);
      expect(value('Orders', 1, 0), order.id);
      expect(value('Orders', 1, 2), customer.id);
      expect(value('OrderItems', 1, 0), item.id);
      expect(value('OrderItems', 1, 1), order.id);
      expect(value('Payments', 1, 0), payment.id);
      expect(value('Payments', 1, 1), order.id);
      final archive = ZipDecoder().decodeBytes(bytes);
      final sheets = archive.files.where(
        (file) => file.name.startsWith('xl/worksheets/sheet'),
      );
      expect(sheets, isNotEmpty);
      for (final sheet in sheets) {
        expect(
          String.fromCharCodes(sheet.content as List<int>),
          contains('state="frozen"'),
        );
      }
    },
  );

  test('palettes change all major regions and a choice persists', () async {
    final defaults = FlyColorScheme.resolve(
      FlyPaletteId.flyDefault,
      Brightness.light,
    );
    for (final palette in FlyPaletteId.values.skip(1)) {
      final colors = FlyColorScheme.resolve(palette, Brightness.light);
      expect(colors.primaryRail, isNot(defaults.primaryRail));
      expect(colors.secondarySidebar, isNot(defaults.secondarySidebar));
      expect(colors.canvas, isNot(defaults.canvas));
      expect(colors.surface, isNot(defaults.surface));
      expect(colors.selected, isNot(defaults.selected));
      expect(colors.accent, isNot(defaults.accent));
    }
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'colorPalette',
            value: FlyPaletteId.ocean.name,
            updatedAt: DateTime(2026, 9, 4),
          ),
        );
    final stored = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals('colorPalette'))).getSingle();
    expect(FlyPaletteIdX.parse(stored.value), FlyPaletteId.ocean);
  });

  test('clarity palette keeps neutral layers and readable accents', () {
    final colors = FlyColorScheme.resolve(
      FlyPaletteId.clarity,
      Brightness.light,
    );
    expect(colors.canvas, isNot(colors.surface));
    expect(colors.secondarySidebar, isNot(colors.canvas));
    expect(colors.primaryRail, isNot(colors.secondarySidebar));
    expect(colors.accent, isNot(colors.success));

    double contrast(Color first, Color second) {
      final a = first.computeLuminance() + .05;
      final b = second.computeLuminance() + .05;
      return a > b ? a / b : b / a;
    }

    expect(contrast(colors.textPrimary, colors.surface), greaterThan(7));
    expect(contrast(colors.textSecondary, colors.surface), greaterThan(4.5));
    expect(contrast(colors.accent, colors.surface), greaterThan(4.5));
    expect(FlyPaletteIdX.parse('clarity'), FlyPaletteId.clarity);
    expect(
      FlyColorScheme.resolve(FlyPaletteId.clarity, Brightness.dark).accent,
      isNot(colors.accent),
    );
  });

  test(
    'Sage Mist replaces legacy graphite and keeps readable layered surfaces',
    () {
      expect(FlyPaletteIdX.parse('graphite'), FlyPaletteId.sageMist);
      expect(FlyPaletteIdX.parse('sageMist'), FlyPaletteId.sageMist);
      expect(
        FlyPaletteId.values.any((palette) => palette.name == 'graphite'),
        isFalse,
      );
      double contrast(Color first, Color second) {
        final a = first.computeLuminance() + .05;
        final b = second.computeLuminance() + .05;
        return a > b ? a / b : b / a;
      }

      for (final brightness in Brightness.values) {
        final colors = FlyColorScheme.resolve(
          FlyPaletteId.sageMist,
          brightness,
        );
        expect(colors.secondarySidebar, isNot(colors.surfaceMuted));
        expect(colors.surfaceMuted, isNot(colors.surface));
        for (final background in [
          colors.canvas,
          colors.surface,
          colors.surfaceMuted,
          colors.secondarySidebar,
        ]) {
          expect(
            contrast(colors.textPrimary, background),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(colors.textSecondary, background),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(colors.accent, background),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(
          contrast(colors.textSecondary, colors.primaryRail),
          greaterThanOrEqualTo(3),
        );
      }
    },
  );

  test('schema 7 preserves V6 rows and propagates explicit currency', () async {
    final previous = drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final directory = await Directory.systemTemp.createTemp('fly-v6-v7-');
    final file = File('${directory.path}${Platform.pathSeparator}fly.db');
    AppDatabase? legacy;
    AppDatabase? migrated;
    try {
      legacy = AppDatabase(NativeDatabase(file));
      await legacy.ensureBuiltInData();
      final crm = DriftCustomerRepository(legacy);
      final orderRepo = DriftOrderRepository(legacy);
      final customer = await crm.createCustomer(name: 'Migration Customer');
      final order = await orderRepo.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-V6-MIGRATION',
      );
      final item = await orderRepo.addProductionItem(
        order.id,
        factoryName: 'Migration Factory',
        productName: 'Migration Product',
        factoryCost: 880000,
      );
      await legacy.customStatement(
        'ALTER TABLE orders DROP COLUMN tax_refund_currency',
      );
      await legacy.customStatement(
        'ALTER TABLE order_production_items DROP COLUMN factory_cost_currency',
      );
      await legacy.customStatement('PRAGMA user_version = 6');
      await legacy.close();
      legacy = null;

      migrated = AppDatabase(NativeDatabase(file));
      final migratedRepo = DriftOrderRepository(migrated);
      final migratedOrder = await migratedRepo.watchOrder(order.id).first;
      final migratedItems = await migratedRepo.watchItems(order.id).first;
      expect(migratedOrder?.orderNumber, 'SO-V6-MIGRATION');
      expect(migratedOrder?.taxRefundCurrency, 'USD');
      expect(migratedItems.single.id, item.id);
      expect(migratedItems.single.factoryCostCurrency, 'USD');
    } finally {
      await legacy?.close();
      await migrated?.close();
      if (await directory.exists()) await directory.delete(recursive: true);
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous;
    }
  });
}
