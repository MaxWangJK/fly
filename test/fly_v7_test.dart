import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/customers/import/customer_import_service.dart';
import 'package:fly/features/dashboard/data/dashboard_service.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/domain/order.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/shared/attachments/attachment.dart';
import 'package:fly/shared/attachments/attachment_storage.dart';
import 'package:fly/shared/attachments/drift_attachment_repository.dart';
import 'package:fly/shared/backup/backup_service.dart';
import 'package:fly/shared/domain/priority.dart';
import 'package:fly/shared/notifications/notification_service.dart';
import 'package:fly/shared/search/global_search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('V7 exchange rates round to two decimals before calculations', () {
    expect(roundExchangeRateMicros(7126000), 7130000);
    expect(roundExchangeRateMicros(7124000), 7120000);
    final summary = OrderFinancialSummary(
      order: _order(exchangeRateMicros: 7126000, salesAmount: 100000),
      items: const [],
      payments: const [],
    );
    expect(summary.roundedExchangeRateMicros, 7130000);
    expect(summary.salesRmb, 713000);
  });

  test('backup restores CRM, order, attachment metadata and file', () async {
    final previous = drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final root = await Directory.systemTemp.createTemp('fly-v7-backup-');
    final sourceRoot = await Directory.systemTemp.createTemp('fly-v7-source-');
    AppDatabase? database;
    AppDatabase? restored;
    try {
      database = AppDatabase.atDataRoot(root.path);
      await database.ensureBuiltInData();
      final customers = DriftCustomerRepository(database);
      final orders = DriftOrderRepository(database);
      final customer = await customers.createCustomer(name: 'Backup Jack');
      final order = await orders.createOrder(
        customerId: customer.id,
        orderNumber: 'SO-BACKUP-001',
      );
      final source = File(p.join(sourceRoot.path, 'PI-001.pdf'));
      await source.writeAsBytes([37, 80, 68, 70, 45, 49]);
      final storage = LocalAttachmentStorage(dataRootPath: root.path);
      final stored = await storage.importFile(
        ownerType: AttachmentOwnerType.customer,
        ownerId: customer.id,
        sourcePath: source.path,
      );
      final attachments = DriftAttachmentRepository(database);
      await attachments.addMetadata(
        id: stored.id,
        ownerType: AttachmentOwnerType.customer,
        ownerId: customer.id,
        fileName: stored.fileName,
        originalName: stored.originalName,
        relativePath: stored.relativePath,
        mimeType: stored.mimeType,
        fileSize: stored.fileSize,
        documentType: '报价',
      );

      final backupService = FlyBackupService(
        database: database,
        dataRootPath: root.path,
        appVersion: 'V7-test',
      );
      final package = await backupService.createBackup(
        now: DateTime(2026, 9, 5, 19),
      );
      expect(await package.exists(), isTrue);

      await customers.softDeleteCustomer(customer.id);
      await orders.softDeleteOrder(order.id);
      await attachments.removeMetadata(stored.id);
      await storage.delete(stored.relativePath);
      final prepared = await backupService.prepareRestore(package.path);
      await database.close();
      database = null;
      await backupService.commitRestore(prepared);

      restored = AppDatabase.atDataRoot(root.path);
      final restoredCustomer = await (restored.select(
        restored.customers,
      )..where((row) => row.id.equals(customer.id))).getSingle();
      final restoredOrder = await (restored.select(
        restored.orders,
      )..where((row) => row.id.equals(order.id))).getSingle();
      final restoredAttachment = await (restored.select(
        restored.attachments,
      )..where((row) => row.id.equals(stored.id))).getSingle();
      expect(restoredCustomer.deletedAt, isNull);
      expect(restoredOrder.deletedAt, isNull);
      expect(restoredAttachment.originalName, 'PI-001.pdf');
      expect(
        await File(storage.absolutePath(restoredAttachment.relativePath))
            .readAsBytes(),
        [37, 80, 68, 70, 45, 49],
      );
    } finally {
      await database?.close();
      await restored?.close();
      if (await root.exists()) await root.delete(recursive: true);
      if (await sourceRoot.exists()) await sourceRoot.delete(recursive: true);
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous;
    }
  });

  test('corrupted backup is rejected without changing current data', () async {
    final root = await Directory.systemTemp.createTemp('fly-v7-corrupt-');
    final database = AppDatabase(
      NativeDatabase(File(p.join(root.path, 'fly.db'))),
    );
    try {
      await database.ensureBuiltInData();
      final customer = await DriftCustomerRepository(database)
          .createCustomer(name: 'Safe Customer');
      final broken = File(p.join(root.path, 'broken.zip'));
      await broken.writeAsBytes([1, 2, 3, 4]);
      final service = FlyBackupService(
        database: database,
        dataRootPath: root.path,
      );
      await expectLater(
        service.prepareRestore(broken.path),
        throwsA(isA<Object>()),
      );
      final current = await (database.select(
        database.customers,
      )..where((row) => row.id.equals(customer.id))).getSingle();
      expect(current.name, 'Safe Customer');
      expect(current.deletedAt, isNull);
    } finally {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('global search finds customer, order, note and task', () async {
    final database = AppDatabase(NativeDatabase.memory());
    try {
      await database.ensureBuiltInData();
      final customers = DriftCustomerRepository(database);
      final orders = DriftOrderRepository(database);
      final tasks = DriftTaskRepository(database);
      final customer = await customers.createCustomer(name: 'Jack');
      await customers.addNote(customer.id, content: '报价已发送');
      await orders.createOrder(customerId: customer.id, orderNumber: 'SO-001');
      await tasks.createTask(title: '跟进 Jack');
      final search = GlobalSearchService(database);

      expect(
        (await search.search('Jack')).any(
          (row) => row.type == SearchResultType.customer && row.title == 'Jack',
        ),
        isTrue,
      );
      expect(
        (await search.search('SO-001')).single.type,
        SearchResultType.order,
      );
      expect(
        (await search.search('报价'))
            .any((row) => row.type == SearchResultType.note),
        isTrue,
      );
      expect(
        (await search.search('跟进 Jack'))
            .any((row) => row.type == SearchResultType.task),
        isTrue,
      );
    } finally {
      await database.close();
    }
  });

  test('customer reminder is delivered only once', () async {
    final database = AppDatabase(NativeDatabase.memory());
    try {
      await database.ensureBuiltInData();
      final customers = DriftCustomerRepository(database);
      final created = await customers.createCustomer(name: 'Reminder Jack');
      await customers.saveCustomer(
        created.copyWith(nextFollowUpDate: DateTime(2026, 9, 5)),
      );
      final gateway = _FakeNotificationGateway();
      final service = NotificationService(
        database,
        gateway,
        now: () => DateTime(2026, 9, 5, 9, 15),
      );
      await service.saveSettings(
        const ReminderSettings(enabled: true, offsetMinutes: {10, 60, 1440}),
      );
      expect(await service.checkAndDeliver(), 1);
      expect(await service.checkAndDeliver(), 0);
      expect(gateway.messages, hasLength(1));
      expect(gateway.messages.single, contains('Reminder Jack'));
      expect(
        await database.select(database.notificationDeliveryLogs).get(),
        hasLength(1),
      );
    } finally {
      await database.close();
    }
  });

  test('next action type persists even when free text is empty', () async {
    final database = AppDatabase(NativeDatabase.memory());
    try {
      await database.ensureBuiltInData();
      final repository = DriftCustomerRepository(database);
      final customer = await repository.createCustomer(name: 'Action Jack');
      await repository.addFollowUp(
        customer.id,
        channel: 'WhatsApp',
        content: '',
        nextActionType: NextActionType.paymentFollowUp,
      );
      final saved = await repository.watchCustomer(customer.id).first;
      final followUp = await repository
          .watchLatestNextAction(customer.id)
          .first;
      expect(saved?.nextActionType, NextActionType.paymentFollowUp);
      expect(saved?.nextAction, isEmpty);
      expect(followUp?.nextActionType, NextActionType.paymentFollowUp);
      expect(followUp?.nextAction, isEmpty);
    } finally {
      await database.close();
    }
  });

  test('dashboard returns exact today and urgent counts', () async {
    final database = AppDatabase(NativeDatabase.memory());
    try {
      await database.ensureBuiltInData();
      final now = DateTime(2026, 9, 5, 10);
      for (var index = 0; index < 3; index++) {
        await database
            .into(database.customers)
            .insert(
              CustomersCompanion.insert(
                id: 'dashboard-customer-$index',
                name: 'Customer $index',
                nextFollowUpDate: drift.Value(DateTime(2026, 9, 5)),
                sortOrder: index,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      for (var index = 0; index < 5; index++) {
        await database
            .into(database.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'dashboard-task-$index',
                title: 'Task $index',
                dueDate: drift.Value(DateTime(2026, 9, 5)),
                sortOrder: index,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      for (var index = 0; index < 2; index++) {
        await database
            .into(database.orders)
            .insert(
              OrdersCompanion.insert(
                id: 'dashboard-order-$index',
                orderNumber: 'SO-URGENT-$index',
                urgency: const drift.Value(true),
                currency: const drift.Value('CNY'),
                baseProfitCurrency: const drift.Value('CNY'),
                orderDate: drift.Value(DateTime(2026, 9, 5)),
                sortOrder: index,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      final result = await DashboardService(database, now: () => now).load();
      expect(result.todayCustomers, hasLength(3));
      expect(result.todayTasks, hasLength(5));
      expect(result.urgentOrders, hasLength(2));
    } finally {
      await database.close();
    }
  });

  test('customer Excel preview marks one new, duplicate and invalid', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final directory = await Directory.systemTemp.createTemp('fly-v7-import-');
    try {
      await database.ensureBuiltInData();
      final repository = DriftCustomerRepository(database);
      final existing = await repository.createCustomer(name: 'Existing');
      await repository.saveCustomer(
        existing.copyWith(email: 'jack@example.com'),
      );
      final workbook = Excel.createExcel();
      final sheet = workbook['Sheet1'];
      sheet.appendRow([
        TextCellValue('客户名称'),
        TextCellValue('Email'),
        TextCellValue('下次跟进'),
      ]);
      sheet.appendRow([
        TextCellValue('New Customer'),
        TextCellValue('new@example.com'),
        TextCellValue('2026-09-10'),
      ]);
      sheet.appendRow([
        TextCellValue('Duplicate Customer'),
        TextCellValue('JACK@example.com'),
        TextCellValue('2026-09-11'),
      ]);
      sheet.appendRow([
        TextCellValue(''),
        TextCellValue('invalid@example.com'),
        TextCellValue('2026-09-12'),
      ]);
      final file = File(p.join(directory.path, 'customers.xlsx'));
      await file.writeAsBytes(workbook.encode()!);
      final service = CustomerImportService(database);
      final sheets = await service.inspect(file.path);
      final mapping = service.autoMap(sheets.single.headers);
      final preview = await service.preview(
        path: file.path,
        sheetName: sheets.single.name,
        mapping: mapping,
      );
      expect(preview, hasLength(3));
      expect(preview.map((row) => row.status), [
        CustomerImportRowStatus.ready,
        CustomerImportRowStatus.duplicate,
        CustomerImportRowStatus.invalid,
      ]);
    } finally {
      await database.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  test(
    'customer attachment survives database restart with correct path',
    () async {
      final root = await Directory.systemTemp.createTemp('fly-v7-attachment-');
      final sourceRoot = await Directory.systemTemp.createTemp('fly-v7-file-');
      AppDatabase? database;
      AppDatabase? reopened;
      try {
        database = AppDatabase.atDataRoot(root.path);
        await database.ensureBuiltInData();
        final customer = await DriftCustomerRepository(database)
            .createCustomer(name: 'Attachment Customer');
        final source = File(p.join(sourceRoot.path, 'contract.pdf'));
        await source.writeAsBytes([10, 20, 30]);
        final storage = LocalAttachmentStorage(dataRootPath: root.path);
        final stored = await storage.importFile(
          ownerType: AttachmentOwnerType.customer,
          ownerId: customer.id,
          sourcePath: source.path,
        );
        await DriftAttachmentRepository(database).addMetadata(
          id: stored.id,
          ownerType: AttachmentOwnerType.customer,
          ownerId: customer.id,
          fileName: stored.fileName,
          originalName: stored.originalName,
          relativePath: stored.relativePath,
          mimeType: stored.mimeType,
          fileSize: stored.fileSize,
          documentType: '合同',
        );
        await database.close();
        database = null;

        reopened = AppDatabase.atDataRoot(root.path);
        final attachment = (await DriftAttachmentRepository(
          reopened,
        ).watchOwner(AttachmentOwnerType.customer, customer.id).first).single;
        final absolute = storage.absolutePath(attachment.relativePath);
        expect(p.isAbsolute(absolute), isTrue);
        expect(await File(absolute).readAsBytes(), [10, 20, 30]);
      } finally {
        await database?.close();
        await reopened?.close();
        if (await root.exists()) await root.delete(recursive: true);
        if (await sourceRoot.exists()) await sourceRoot.delete(recursive: true);
      }
    },
  );

  test(
    'schema 8 preserves V7 data and projects order files to attachments',
    () async {
      final previous = drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp('fly-v7-v8-');
      final file = File(p.join(directory.path, 'fly.db'));
      AppDatabase? legacy;
      AppDatabase? migrated;
      try {
        legacy = AppDatabase(NativeDatabase(file));
        await legacy.ensureBuiltInData();
        final customers = DriftCustomerRepository(legacy);
        final orders = DriftOrderRepository(legacy);
        final customer = await customers.createCustomer(name: 'V7 Customer');
        final order = await orders.createOrder(
          customerId: customer.id,
          orderNumber: 'SO-V7-MIGRATION',
        );
        final now = DateTime(2026, 9, 5);
        await legacy
            .into(legacy.orderFiles)
            .insert(
              OrderFilesCompanion.insert(
                id: 'legacy-order-file',
                orderId: order.id,
                fileName: 'legacy.pdf',
                originalName: 'PI.pdf',
                localRelativePath: p.join(
                  'orders',
                  order.id,
                  'PI',
                  'legacy.pdf',
                ),
                fileSize: 42,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await legacy.customStatement('DROP TABLE attachments');
        await legacy.customStatement('DROP TABLE notification_delivery_logs');
        await legacy.customStatement(
          'ALTER TABLE customers DROP COLUMN next_action_type',
        );
        await legacy.customStatement(
          'ALTER TABLE customer_follow_ups DROP COLUMN next_action_type',
        );
        await legacy.customStatement('PRAGMA user_version = 7');
        await legacy.close();
        legacy = null;

        migrated = AppDatabase(NativeDatabase(file));
        final savedCustomer = await (migrated.select(
          migrated.customers,
        )..where((row) => row.id.equals(customer.id))).getSingle();
        final savedOrder = await (migrated.select(
          migrated.orders,
        )..where((row) => row.id.equals(order.id))).getSingle();
        final attachment = await (migrated.select(
          migrated.attachments,
        )..where((row) => row.id.equals('legacy-order-file'))).getSingle();
        expect(savedCustomer.name, 'V7 Customer');
        expect(savedCustomer.nextActionType, isNull);
        expect(savedOrder.orderNumber, 'SO-V7-MIGRATION');
        expect(attachment.ownerType, 'order');
        expect(attachment.ownerId, order.id);
        expect(attachment.originalName, 'PI.pdf');
      } finally {
        await legacy?.close();
        await migrated?.close();
        if (await directory.exists()) await directory.delete(recursive: true);
        drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous;
      }
    },
  );
}

SalesOrder _order({required int exchangeRateMicros, required int salesAmount}) {
  final now = DateTime(2026, 9, 5);
  return SalesOrder(
    id: 'fx-order',
    orderNumber: 'SO-FX',
    priority: PriorityLevel.low,
    importance: false,
    urgency: false,
    currency: 'USD',
    baseProfitCurrency: 'CNY',
    exchangeRateMicros: exchangeRateMicros,
    salesAmount: salesAmount,
    taxRefund: 0,
    inlandCost: 0,
    portCharges: 0,
    otherCost: 0,
    otherIncome: 0,
    notes: '',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    version: 1,
  );
}

class _FakeNotificationGateway implements NotificationGateway {
  final List<String> messages = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    messages.add('$title $body $payload');
  }
}
