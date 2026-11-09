import 'dart:io';

import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/import/customer_import_service.dart';

void main() {
  late AppDatabase db;
  late Directory directory;
  late CustomerImportService service;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureBuiltInData();
    directory = await Directory.systemTemp.createTemp(
      'fly-customer-simple-import-',
    );
    service = CustomerImportService(db);
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<List<CustomerImportRow>> prepare(List<List<String>> rows) async {
    final book = Excel.decodeBytes(service.buildTemplate());
    final sheet = book['Customers'];
    for (final row in rows) {
      sheet.appendRow(row.map(TextCellValue.new).toList());
    }
    final file = File('${directory.path}/customers.xlsx');
    await file.writeAsBytes(book.encode()!);
    final inspected = (await service.inspect(file.path)).single;
    return service.preview(
      path: file.path,
      sheetName: inspected.name,
      mapping: service.autoMap(inspected.headers),
      requireProfile: true,
    );
  }

  test('template is empty, simple and puts required profile fields first', () {
    final sheet = Excel.decodeBytes(service.buildTemplate())
        .tables['Customers']!;
    expect(sheet.maxColumns, 11);
    expect(sheet.maxRows, 1);
    final headers = sheet.rows.single.map((c) => c!.value.toString()).toList();
    expect(headers.take(5), ['客户名称 *', '国家 *', '客户级别 *', '客户状态 *', '客户来源']);
    expect(
      headers,
      containsAll(['公司', 'Email', 'Phone', 'WeChat', 'WhatsApp']),
    );
    expect(
      service.autoMap(headers).values.toSet(),
      containsAll([
        CustomerImportField.name,
        CustomerImportField.country,
        CustomerImportField.category,
        CustomerImportField.status,
        CustomerImportField.wechat,
      ]),
    );
  });

  test(
    'strict template validates four required fields and fixed five statuses',
    () async {
      final rows = await prepare([
        ['Alex', 'Australia', 'A', '新客户', 'Exhibition'],
        ['Missing country', '', 'A', '新客户'],
        ['Missing level', 'Australia', '', '新客户'],
        ['Wrong status', 'Australia', 'B', 'Made-up status'],
        ['Wrong level', 'Australia', 'Unknown', '新客户'],
      ]);
      expect(rows.map((r) => r.status), [
        CustomerImportRowStatus.ready,
        CustomerImportRowStatus.invalid,
        CustomerImportRowStatus.invalid,
        CustomerImportRowStatus.invalid,
        CustomerImportRowStatus.invalid,
      ]);
      final result = await service.import(rows: rows, requireProfile: true);
      expect(result.created, 1);
      expect(result.failedReasons, hasLength(4));
      final record = await db.select(db.customers).getSingle();
      expect(record.categoryId, 'category-a');
      expect(record.statusId, 'customer-new');
      expect(
        (await db.select(db.customerStatuses).get()).where(
          (s) => s.name == 'Made-up status',
        ),
        isEmpty,
      );
      final category = await (db.select(
        db.customerCategories,
      )..where((r) => r.id.equals('category-a'))).getSingle();
      expect(
        (await db.select(db.customerTagLinks).get()).any(
          (l) => l.customerId == record.id && l.tagId == category.tagId,
        ),
        isTrue,
      );
    },
  );

  test(
    'optional contact values persist and imported profiles enter sync outbox',
    () async {
      final rows = await prepare([
        [
          'Mira',
          'Canada',
          'B级',
          'Interested',
          'Website',
          'Example Trade',
          'mira@example.test',
          '+1 555 1234',
          'mira-id',
          '+1 555 4567',
          'Sample inquiry',
        ],
      ]);
      final result = await service.import(rows: rows, requireProfile: true);
      expect(result.created, 1);
      final record = await db.select(db.customers).getSingle();
      expect(result.firstCustomerId, record.id);
      expect(record.companyName, 'Example Trade');
      expect(record.email, 'mira@example.test');
      expect(record.wechat, 'mira-id');
      expect(record.statusId, 'customer-intent');
      expect(
        (await db
                .customSelect(
                  "SELECT entity_type FROM sync_outbox WHERE entity_type='customers'",
                )
                .get())
            .isNotEmpty,
        isTrue,
      );
    },
  );

  test(
    'in-file duplicates are previewed and skipped or overwritten consistently',
    () async {
      final rows = await prepare([
        ['Alex', 'Australia', 'A', '新客户', '', '', 'same@example.test'],
        ['Alex revised', 'Australia', 'B', '意向客户', '', '', 'SAME@example.test'],
      ]);
      expect(rows.last.status, CustomerImportRowStatus.duplicate);
      final result = await service.import(rows: rows, requireProfile: true);
      expect(result.created, 1);
      expect(result.skipped, 1);
      final overwrite = await service.import(
        rows: [rows.last],
        duplicateAction: DuplicateImportAction.overwrite,
        requireProfile: true,
      );
      expect(overwrite.updated, 1);
      expect((await db.select(db.customers).getSingle()).name, 'Alex revised');
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test('overwrite keeps unfilled optional fields, original creation time and advances version', () async {
    final repo = DriftCustomerRepository(db);
    final customer = await repo.createCustomer(
      name: 'Keep details',
      country: 'Canada',
      categoryId: 'category-a',
    );
    await repo.saveCustomer(
      customer.copyWith(
        email: 'keep@example.test',
        phone: '+1 555 9999',
        notes: 'existing note',
      ),
    );
    final before = await db.select(db.customers).getSingle();
    final rows = await prepare([
      ['Keep details', 'Canada', 'B', '成交客户'],
    ]);
    final result = await service.import(
      rows: rows,
      duplicateAction: DuplicateImportAction.overwrite,
      requireProfile: true,
    );
    expect(result.updated, 1);
    final after = await db.select(db.customers).getSingle();
    expect(after.email, before.email);
    expect(after.phone, before.phone);
    expect(after.notes, before.notes);
    expect(after.createdAt, before.createdAt);
    expect(after.version, greaterThan(before.version));
    expect(after.categoryId, 'category-b');
  }, timeout: const Timeout(Duration(seconds: 15)));
}
