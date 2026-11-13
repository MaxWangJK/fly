import 'dart:io';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/domain/priority.dart';
import '../data/drift_customer_repository.dart';
import '../domain/customer_lifecycle.dart';
import '../domain/customer_name.dart';

enum CustomerImportField {
  name,
  category,
  company,
  country,
  city,
  whatsapp,
  email,
  phone,
  facebook,
  wechat,
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
    CustomerImportField.category => '客户级别',
    CustomerImportField.company => '公司',
    CustomerImportField.country => '国家',
    CustomerImportField.city => '城市',
    CustomerImportField.whatsapp => 'WhatsApp',
    CustomerImportField.email => 'Email',
    CustomerImportField.phone => 'Phone',
    CustomerImportField.facebook => 'Facebook',
    CustomerImportField.wechat => 'WeChat',
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
    this.firstCustomerId,
  });
  final int created;
  final int updated;
  final int skipped;
  final List<String> failedReasons;
  final String? firstCustomerId;
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
    bool requireProfile = false,
  }) async {
    final book = Excel.decodeBytes(await File(path).readAsBytes());
    final sheet = book.tables[sheetName];
    if (sheet == null) throw StateError('找不到 Sheet：$sheetName');
    final existing = await (_db.select(
      _db.customers,
    )..where((row) => row.deletedAt.isNull())).get();
    final result = <CustomerImportRow>[];
    final seen = <Map<CustomerImportField, String>>[];
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
      try {
        await _validateProfile(values, required: requireProfile);
      } on Object catch (error) {
        result.add(
          CustomerImportRow(
            rowNumber: index + 1,
            values: values,
            status: CustomerImportRowStatus.invalid,
            reason: '$error',
          ),
        );
        continue;
      }
      final duplicate = existing
          .where((customer) => _isDuplicate(customer, values))
          .firstOrNull;
      final duplicateInFile = seen.any(
        (previous) => _sameIncoming(previous, values),
      );
      result.add(
        CustomerImportRow(
          rowNumber: index + 1,
          values: values,
          status: duplicate == null && !duplicateInFile
              ? CustomerImportRowStatus.ready
              : CustomerImportRowStatus.duplicate,
          duplicateCustomerId: duplicate?.id,
          reason: duplicate != null
              ? '客户名称或联系方式重复'
              : duplicateInFile
              ? '当前文件中有重复客户'
              : null,
        ),
      );
      seen.add(values);
    }
    return result;
  }

  Future<CustomerImportResult> import({
    required List<CustomerImportRow> rows,
    DuplicateImportAction duplicateAction = DuplicateImportAction.skip,
    bool requireProfile = false,
  }) async {
    var created = 0;
    var updated = 0;
    var skipped = 0;
    final failed = <String>[];
    String? firstCustomerId;
    await _db.transaction(() async {
      for (final row in rows) {
        if (row.status == CustomerImportRowStatus.invalid) {
          failed.add('第 ${row.rowNumber} 行：${row.reason}');
          continue;
        }
        try {
          await _validateProfile(row.values, required: requireProfile);
          // Recheck against current data, including earlier rows in this file.
          final existing = await (_db.select(
            _db.customers,
          )..where((r) => r.deletedAt.isNull())).get();
          final duplicate = existing
              .where((r) => _isDuplicate(r, row.values))
              .firstOrNull;
          if (duplicate != null &&
              duplicateAction == DuplicateImportAction.skip) {
            skipped += 1;
            continue;
          }
          final overwriteId =
              duplicate != null &&
                  duplicateAction == DuplicateImportAction.overwrite
              ? duplicate.id
              : null;
          final savedId = await _db.transaction(() async {
            final customerId = await _saveCustomer(
              row.values,
              overwriteId: overwriteId,
            );
            await _saveTags(
              customerId,
              row.values[CustomerImportField.tags] ?? '',
            );
            return customerId;
          });
          firstCustomerId ??= savedId;
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
      firstCustomerId: firstCustomerId,
    );
  }

  Uint8List buildTemplate({String Function(String)? translate}) {
    String copy(String value) => translate?.call(value) ?? value;
    final book = Excel.createExcel();
    book.rename('Sheet1', 'Customers');
    final sheet = book['Customers'];
    const columns = [
      CustomerImportField.name,
      CustomerImportField.country,
      CustomerImportField.category,
      CustomerImportField.status,
      CustomerImportField.source,
      CustomerImportField.company,
      CustomerImportField.email,
      CustomerImportField.phone,
      CustomerImportField.wechat,
      CustomerImportField.whatsapp,
      CustomerImportField.notes,
    ];
    const required = {
      CustomerImportField.name,
      CustomerImportField.country,
      CustomerImportField.category,
      CustomerImportField.status,
    };
    sheet.appendRow(
      columns
          .map(
            (field) => TextCellValue(
              '${copy(field.label)}${required.contains(field) ? ' *' : ''}',
            ),
          )
          .toList(),
    );
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

  Future<void> _validateProfile(
    Map<CustomerImportField, String> values, {
    required bool required,
  }) async {
    String value(CustomerImportField field) => values[field]?.trim() ?? '';
    if (required &&
        [
          CustomerImportField.name,
          CustomerImportField.country,
          CustomerImportField.category,
          CustomerImportField.status,
        ].any((field) => value(field).isEmpty)) {
      throw const FormatException('客户名称、国家、级别、状态为必填项');
    }
    if (value(CustomerImportField.name).length > 240) {
      throw const FormatException('客户名称最多240字');
    }
    if (value(CustomerImportField.status).length > 120) {
      throw const FormatException('客户状态名称需要1–120字');
    }
    if (value(CustomerImportField.category).length > 80) {
      throw const FormatException('客户级别最多80字');
    }
  }

  Future<String> _statusId(String raw) async {
    final name = raw.trim();
    final key = DriftCustomerRepository.statusNameKey(name);
    final repository = DriftCustomerRepository(_db);
    final statuses = await repository
        .watchStatuses(includeInactive: true)
        .first;
    var existing = statuses
        .where(
          (s) =>
              !CustomerLifecycle.legacyIds.contains(s.id) &&
              (s.id.toLowerCase() == key ||
                  DriftCustomerRepository.statusNameKey(s.name) == key),
        )
        .firstOrNull;
    final match = CustomerLifecycle.stages
        .where((s) => [s.$1, s.$2, s.$3.toLowerCase()].contains(key))
        .firstOrNull;
    if (existing == null && match != null) {
      existing = statuses
          .where(
            (s) =>
                s.id == match.$1 &&
                (s.name == match.$2 || s.name == match.$3 || key == s.id),
          )
          .firstOrNull;
    }
    if (existing != null) {
      if (!existing.isActive) {
        await repository.setStatusActive(existing.id, active: true);
      }
      return existing.id;
    }
    return (await repository.createStatus(name)).id;
  }

  Future<String?> _categoryId(String raw) async {
    if (raw.trim().isEmpty) return null;
    String normalize(String value) {
      final key = value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      final grade = RegExp(
        r'^(?:(?:grade|level)\s*)?([a-z])(?:\s*级)?(?:\s*客户)?$',
      ).firstMatch(key);
      return grade?.group(1) ?? key;
    }

    final categories =
        await (_db.select(_db.customerCategories)
              ..where((r) => r.deletedAt.isNull())
              ..orderBy([
                (r) => OrderingTerm.desc(r.isActive),
                (r) => OrderingTerm.asc(r.sortOrder),
              ]))
            .get();
    final category = categories
        .where(
          (r) =>
              r.id.toLowerCase() == raw.toLowerCase() ||
              normalize(r.name) == normalize(raw),
        )
        .firstOrNull;
    final repository = DriftCustomerRepository(_db);
    if (category == null) {
      return (await repository.createCategory(raw.trim())).id;
    }
    if (!category.isActive) {
      await repository.setCategoryActive(category.id, active: true);
    }
    return category.id;
  }

  Future<String> _saveCustomer(
    Map<CustomerImportField, String> values, {
    String? overwriteId,
  }) async {
    String? optional(CustomerImportField field) {
      final text = values[field]?.trim() ?? '';
      return text.isEmpty ? null : text;
    }

    final repository = DriftCustomerRepository(_db);
    final category = await _categoryId(
      optional(CustomerImportField.category) ?? '',
    );
    final status = optional(CustomerImportField.status);
    final statusId = status == null ? null : await _statusId(status);
    final customer = overwriteId == null
        ? await repository.createCustomer(
            name: values[CustomerImportField.name]!,
            country: optional(CustomerImportField.country) ?? '',
            categoryId: category,
            statusId: statusId,
          )
        : await repository.watchCustomer(overwriteId).first;
    if (customer == null) throw StateError('需要覆盖的客户不存在');
    final notes = optional(CustomerImportField.notes);
    await repository.saveCustomer(
      customer.copyWith(
        name: values[CustomerImportField.name]!.trim(),
        country: optional(CustomerImportField.country),
        categoryId: category ?? customer.categoryId,
        statusId: statusId ?? customer.statusId,
        companyName: optional(CustomerImportField.company),
        city: optional(CustomerImportField.city),
        email: optional(CustomerImportField.email),
        phone: optional(CustomerImportField.phone),
        whatsapp: optional(CustomerImportField.whatsapp),
        facebook: optional(CustomerImportField.facebook),
        wechat: optional(CustomerImportField.wechat),
        notes: notes,
        priority: optional(CustomerImportField.priority) == null
            ? customer.priority
            : PriorityLevel.values.firstWhere(
                (v) =>
                    v.name == _priority(values[CustomerImportField.priority]!),
              ),
        nextFollowUpDate: optional(CustomerImportField.nextFollowUp) == null
            ? customer.nextFollowUpDate
            : DateTime.parse(values[CustomerImportField.nextFollowUp]!),
      ),
    );
    final source = optional(CustomerImportField.source);
    if (source != null) {
      await repository.setCustomerSourceText(customer.id, source);
    }
    if (notes != null) await repository.addNote(customer.id, content: notes);
    return customer.id;
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
    return normalizeCustomerName(customer.name) ==
            normalizeCustomerName(values[CustomerImportField.name] ?? '') ||
        (email.isNotEmpty && customer.emailNormalized == email) ||
        (whatsapp.isNotEmpty && customer.whatsappNormalized == whatsapp) ||
        (phone.isNotEmpty && customer.phoneNormalized == phone);
  }

  bool _sameIncoming(
    Map<CustomerImportField, String> a,
    Map<CustomerImportField, String> b,
  ) =>
      normalizeCustomerName(a[CustomerImportField.name] ?? '') ==
          normalizeCustomerName(b[CustomerImportField.name] ?? '') ||
      [
        CustomerImportField.email,
        CustomerImportField.phone,
        CustomerImportField.whatsapp,
      ].any((field) {
        final left = field == CustomerImportField.email
            ? _normalizeEmail(a[field] ?? '')
            : _normalizePhone(a[field] ?? '');
        final right = field == CustomerImportField.email
            ? _normalizeEmail(b[field] ?? '')
            : _normalizePhone(b[field] ?? '');
        return left.isNotEmpty && left == right;
      });

  static String _cellText(Data? data) => data?.value?.toString().trim() ?? '';
  static String _normalizeHeader(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s_\-*＊]'), '');
  static String _normalizeEmail(String value) => value.trim().toLowerCase();
  static String _normalizePhone(String value) =>
      value.replaceAll(RegExp(r'\D'), '');
  static String _priority(String value) => switch (value.trim().toLowerCase()) {
    '高' || 'high' => 'high',
    '中' || 'medium' => 'medium',
    _ => 'low',
  };

  static const Map<CustomerImportField, Set<String>> _aliases = {
    CustomerImportField.name: {
      'name',
      'customername',
      '客户名称',
      '客户名',
      '客户',
      '客户姓名',
    },
    CustomerImportField.category: {
      'category',
      'level',
      'grade',
      'customercategory',
      'customercategories',
      'customerlevel',
      '客户级别',
      '级别',
      '等级',
    },
    CustomerImportField.company: {
      'company',
      'companyname',
      '公司',
      '公司名称',
      '公司名字',
    },
    CustomerImportField.country: {'country', '国家'},
    CustomerImportField.city: {'city', '城市'},
    CustomerImportField.whatsapp: {'whatsapp', 'wa'},
    CustomerImportField.email: {'email', '邮箱'},
    CustomerImportField.phone: {'phone', '电话', '手机'},
    CustomerImportField.facebook: {'facebook', 'fb'},
    CustomerImportField.wechat: {'wechat', '微信', '通讯账号'},
    CustomerImportField.status: {'status', 'customerstatus', '客户状态', '状态'},
    CustomerImportField.source: {'source', 'customersource', '客户来源', '来源'},
    CustomerImportField.priority: {'priority', '优先级'},
    CustomerImportField.nextFollowUp: {'nextfollowup', '下次跟进', '跟进日期'},
    CustomerImportField.notes: {'notes', 'note', '备注'},
    CustomerImportField.tags: {'tags', 'tag', '标签'},
  };
}
