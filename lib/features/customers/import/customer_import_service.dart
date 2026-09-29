import 'dart:io';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

enum CustomerImportField {
  name,
  company,
  country,
  city,
  whatsapp,
  email,
  phone,
  facebook,
  status,
  source,
  priority,
  nextFollowUp,
  notes,
  tags,
}

extension CustomerImportFieldX on CustomerImportField {
  String get label => switch (this) {
    CustomerImportField.name => '客户名称',
    CustomerImportField.company => '公司',
    CustomerImportField.country => '国家',
    CustomerImportField.city => '城市',
    CustomerImportField.whatsapp => 'WhatsApp',
    CustomerImportField.email => 'Email',
    CustomerImportField.phone => 'Phone',
    CustomerImportField.facebook => 'Facebook',
    CustomerImportField.status => '客户状态',
    CustomerImportField.source => '客户来源',
    CustomerImportField.priority => '优先级',
    CustomerImportField.nextFollowUp => '下次跟进',
    CustomerImportField.notes => '备注',
    CustomerImportField.tags => 'Tags',
  };
}

enum CustomerImportRowStatus { ready, duplicate, invalid }

enum DuplicateImportAction { skip, overwrite, create }

class CustomerImportSheet {
  const CustomerImportSheet({required this.name, required this.headers});
  final String name;
  final List<String> headers;
}

class CustomerImportRow {
  const CustomerImportRow({
    required this.rowNumber,
    required this.values,
    required this.status,
    this.duplicateCustomerId,
    this.reason,
  });
  final int rowNumber;
  final Map<CustomerImportField, String> values;
  final CustomerImportRowStatus status;
  final String? duplicateCustomerId;
  final String? reason;
}

class CustomerImportResult {
  const CustomerImportResult({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.failedReasons,
  });
  final int created;
  final int updated;
  final int skipped;
  final List<String> failedReasons;
}

class CustomerImportService {
  CustomerImportService(this._db, [this._uuid = const Uuid()]);

  final AppDatabase _db;
  final Uuid _uuid;

  Future<List<CustomerImportSheet>> inspect(String path) async {
    final book = Excel.decodeBytes(await File(path).readAsBytes());
    return [
      for (final entry in book.tables.entries)
        CustomerImportSheet(
          name: entry.key,
          headers: entry.value.rows.isEmpty
              ? const []
              : entry.value.rows.first.map(_cellText).toList(),
        ),
    ];
  }

  Map<int, CustomerImportField> autoMap(List<String> headers) {
    final result = <int, CustomerImportField>{};
    for (var index = 0; index < headers.length; index++) {
      final normalized = _normalizeHeader(headers[index]);
      final field = _aliases.entries
          .where((entry) => entry.value.contains(normalized))
          .map((entry) => entry.key)
          .firstOrNull;
      if (field != null && !result.containsValue(field)) result[index] = field;
    }
    return result;
  }

  Future<List<CustomerImportRow>> preview({
    required String path,
    required String sheetName,
    required Map<int, CustomerImportField> mapping,
  }) async {
    final book = Excel.decodeBytes(await File(path).readAsBytes());
    final sheet = book.tables[sheetName];
    if (sheet == null) throw StateError('找不到 Sheet：$sheetName');
    final existing = await (_db.select(
      _db.customers,
    )..where((row) => row.deletedAt.isNull())).get();
    final result = <CustomerImportRow>[];
    for (var index = 1; index < sheet.rows.length; index++) {
      final row = sheet.rows[index];
      final values = <CustomerImportField, String>{};
      for (final entry in mapping.entries) {
        values[entry.value] = entry.key < row.length
            ? _cellText(row[entry.key])
            : '';
      }
      if (values.values.every((value) => value.trim().isEmpty)) continue;
      final name = values[CustomerImportField.name]?.trim() ?? '';
      if (name.isEmpty) {
        result.add(
          CustomerImportRow(
            rowNumber: index + 1,
            values: values,
            status: CustomerImportRowStatus.invalid,
            reason: '缺少客户名称',
          ),
        );
        continue;
      }
      final nextDate = values[CustomerImportField.nextFollowUp]?.trim() ?? '';
      if (nextDate.isNotEmpty && DateTime.tryParse(nextDate) == null) {
        result.add(
          CustomerImportRow(
            rowNumber: index + 1,
            values: values,
            status: CustomerImportRowStatus.invalid,
            reason: '下次跟进日期格式错误',
          ),
        );
        continue;
      }
      final duplicate = existing
          .where((customer) => _isDuplicate(customer, values))
          .firstOrNull;
      result.add(
        CustomerImportRow(
          rowNumber: index + 1,
          values: values,
          status: duplicate == null
              ? CustomerImportRowStatus.ready
              : CustomerImportRowStatus.duplicate,
          duplicateCustomerId: duplicate?.id,
          reason: duplicate == null ? null : 'Email / WhatsApp / Phone 重复',
        ),
      );
    }
    return result;
  }

  Future<CustomerImportResult> import({
    required List<CustomerImportRow> rows,
    DuplicateImportAction duplicateAction = DuplicateImportAction.skip,
  }) async {
    var created = 0;
    var updated = 0;
    var skipped = 0;
    final failed = <String>[];
    await _db.transaction(() async {
      for (final row in rows) {
        if (row.status == CustomerImportRowStatus.invalid) {
          failed.add('第 ${row.rowNumber} 行：${row.reason}');
          continue;
        }
        if (row.status == CustomerImportRowStatus.duplicate &&
            duplicateAction == DuplicateImportAction.skip) {
          skipped += 1;
          continue;
        }
        try {
          final overwriteId =
              row.status == CustomerImportRowStatus.duplicate &&
                  duplicateAction == DuplicateImportAction.overwrite
              ? row.duplicateCustomerId
              : null;
          final customerId = overwriteId ?? _uuid.v7();
          await _saveCustomer(
            customerId,
            row.values,
            overwrite: overwriteId != null,
          );
          await _saveTags(
            customerId,
            row.values[CustomerImportField.tags] ?? '',
          );
          overwriteId == null ? created += 1 : updated += 1;
        } on Object catch (error) {
          failed.add('第 ${row.rowNumber} 行：$error');
        }
      }
    });
    return CustomerImportResult(
      created: created,
      updated: updated,
      skipped: skipped,
      failedReasons: failed,
    );
  }

  Uint8List buildTemplate({String Function(String)? translate}) {
    String copy(String value) => translate?.call(value) ?? value;
    final book = Excel.createExcel();
    book.rename('Sheet1', 'Customers');
    final sheet = book['Customers'];
    sheet.appendRow(
      CustomerImportField.values
          .map((field) => TextCellValue(copy(field.label)))
          .toList(),
    );
    sheet.appendRow([
      TextCellValue('Jack'),
      TextCellValue('Jack Trading'),
      TextCellValue('Philippines'),
      TextCellValue('Manila'),
      TextCellValue('+63 900 000 0000'),
      TextCellValue('jack@example.com'),
      TextCellValue('+63 2 8000 0000'),
      TextCellValue('jack.trading'),
      TextCellValue(copy('意向客户')),
      TextCellValue('Alibaba'),
      TextCellValue(copy('高')),
      TextCellValue('2026-09-10'),
      TextCellValue(copy('客户偏好 WPC')),
      TextCellValue(copy('菲律宾,WPC,A级')),
    ]);
    for (var index = 0; index < sheet.maxColumns; index++) {
      sheet.setColumnWidth(index, 18);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: index, rowIndex: 0))
          .cellStyle = CellStyle(
        bold: true,
      );
    }
    final bytes = book.encode();
    if (bytes == null) throw StateError(copy('客户导入模板生成失败'));
    return Uint8List.fromList(bytes);
  }

  Future<void> _saveCustomer(
    String id,
    Map<CustomerImportField, String> values, {
    required bool overwrite,
  }) async {
    final now = DateTime.now();
    final name = values[CustomerImportField.name]!.trim();
    final email = values[CustomerImportField.email]?.trim() ?? '';
    final whatsapp = values[CustomerImportField.whatsapp]?.trim() ?? '';
    final phone = values[CustomerImportField.phone]?.trim() ?? '';
    final statusId = await _findOrCreateStatus(
      values[CustomerImportField.status]?.trim() ?? '',
      now,
    );
    final sourceId = await _findOrCreateSource(
      values[CustomerImportField.source]?.trim() ?? '',
      now,
    );
    final notes = values[CustomerImportField.notes]?.trim() ?? '';
    final companion = CustomersCompanion(
      id: Value(id),
      name: Value(name),
      companyName: Value(values[CustomerImportField.company]?.trim() ?? ''),
      country: Value(values[CustomerImportField.country]?.trim() ?? ''),
      city: Value(values[CustomerImportField.city]?.trim() ?? ''),
      whatsapp: Value(whatsapp),
      email: Value(email),
      phone: Value(phone),
      facebook: Value(values[CustomerImportField.facebook]?.trim() ?? ''),
      emailNormalized: Value(_normalizeEmail(email)),
      whatsappNormalized: Value(_normalizePhone(whatsapp)),
      phoneNormalized: Value(_normalizePhone(phone)),
      statusId: Value(statusId),
      sourceId: Value(sourceId),
      priority: Value(_priority(values[CustomerImportField.priority] ?? '')),
      notes: Value(notes),
      nextFollowUpDate: Value(
        DateTime.tryParse(values[CustomerImportField.nextFollowUp] ?? ''),
      ),
      sortOrder: Value(now.microsecondsSinceEpoch),
      createdAt: Value(now),
      updatedAt: Value(now),
      deletedAt: const Value(null),
      version: const Value(1),
    );
    if (overwrite) {
      await (_db.update(
        _db.customers,
      )..where((row) => row.id.equals(id))).write(
        companion.copyWith(
          id: const Value.absent(),
          createdAt: const Value.absent(),
        ),
      );
    } else {
      await _db.into(_db.customers).insert(companion);
    }
    if (notes.isNotEmpty) {
      await _db
          .into(_db.customerNotes)
          .insert(
            CustomerNotesCompanion.insert(
              id: _uuid.v7(),
              customerId: id,
              content: Value(notes),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
  }

  Future<String?> _findOrCreateStatus(String name, DateTime now) async {
    if (name.isEmpty) return null;
    final existing =
        await (_db.select(_db.customerStatuses)..where(
              (row) =>
                  row.name.lower().equals(name.toLowerCase()) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    final id = _uuid.v7();
    await _db
        .into(_db.customerStatuses)
        .insert(
          CustomerStatusesCompanion.insert(
            id: id,
            name: name,
            sortOrder: now.microsecondsSinceEpoch,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<String?> _findOrCreateSource(String name, DateTime now) async {
    if (name.isEmpty) return null;
    final existing =
        await (_db.select(_db.customerSources)..where(
              (row) =>
                  row.name.lower().equals(name.toLowerCase()) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    final id = _uuid.v7();
    await _db
        .into(_db.customerSources)
        .insert(
          CustomerSourcesCompanion.insert(
            id: id,
            name: name,
            sortOrder: now.microsecondsSinceEpoch,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> _saveTags(String customerId, String raw) async {
    final names = raw
        .split(RegExp(r'[,，;；]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    for (final name in names) {
      final existing =
          await (_db.select(_db.tags)..where(
                (row) =>
                    row.name.lower().equals(name.toLowerCase()) &
                    row.scope.equals('customer') &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      final tagId = existing?.id ?? _uuid.v7();
      if (existing == null) {
        final now = DateTime.now();
        await _db
            .into(_db.tags)
            .insert(
              TagsCompanion.insert(
                id: tagId,
                name: name,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      await _db
          .into(_db.customerTagLinks)
          .insert(
            CustomerTagLinksCompanion.insert(
              customerId: customerId,
              tagId: tagId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  bool _isDuplicate(
    CustomerRecord customer,
    Map<CustomerImportField, String> values,
  ) {
    final email = _normalizeEmail(values[CustomerImportField.email] ?? '');
    final whatsapp = _normalizePhone(
      values[CustomerImportField.whatsapp] ?? '',
    );
    final phone = _normalizePhone(values[CustomerImportField.phone] ?? '');
    return (email.isNotEmpty && customer.emailNormalized == email) ||
        (whatsapp.isNotEmpty && customer.whatsappNormalized == whatsapp) ||
        (phone.isNotEmpty && customer.phoneNormalized == phone);
  }

  static String _cellText(Data? data) => data?.value?.toString().trim() ?? '';
  static String _normalizeHeader(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
  static String _normalizeEmail(String value) => value.trim().toLowerCase();
  static String _normalizePhone(String value) =>
      value.replaceAll(RegExp(r'\D'), '');
  static String _priority(String value) => switch (value.trim().toLowerCase()) {
    '高' || 'high' => 'high',
    '中' || 'medium' => 'medium',
    _ => 'low',
  };

  static const Map<CustomerImportField, Set<String>> _aliases = {
    CustomerImportField.name: {'name', 'customername', '客户名称', '客户名'},
    CustomerImportField.company: {'company', 'companyname', '公司', '公司名称'},
    CustomerImportField.country: {'country', '国家'},
    CustomerImportField.city: {'city', '城市'},
    CustomerImportField.whatsapp: {'whatsapp', 'wa'},
    CustomerImportField.email: {'email', '邮箱'},
    CustomerImportField.phone: {'phone', '电话', '手机'},
    CustomerImportField.facebook: {'facebook', 'fb'},
    CustomerImportField.status: {'status', 'customerstatus', '客户状态', '状态'},
    CustomerImportField.source: {'source', 'customersource', '客户来源', '来源'},
    CustomerImportField.priority: {'priority', '优先级'},
    CustomerImportField.nextFollowUp: {'nextfollowup', '下次跟进', '跟进日期'},
    CustomerImportField.notes: {'notes', 'note', '备注'},
    CustomerImportField.tags: {'tags', 'tag', '标签'},
  };
}
