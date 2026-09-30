import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/data/tag_garbage_collector.dart';
import '../../../shared/domain/priority.dart';
import '../../../shared/domain/tag_lifecycle.dart';
import '../../../shared/search/fuzzy_match.dart';
import '../domain/customer.dart';
import '../domain/customer_name.dart';
import '../domain/customer_repository.dart';

class DriftCustomerRepository implements CustomerRepository {
  DriftCustomerRepository(this._db);

  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  Future<List<Customer>> seedDevelopmentData({DateTime? today}) async {
    final existing = await watchCustomers(
      const CustomerQuery(projection: CustomerProjection.all),
    ).first;
    if (existing.isNotEmpty) return existing;
    final categories = await watchCategories().first;
    final statuses = await watchStatuses().first;
    final sources = await watchSources().first;
    String? category(String name) =>
        categories.where((item) => item.name == name).firstOrNull?.id;
    String? status(String name) =>
        statuses.where((item) => item.name == name).firstOrNull?.id;
    String? source(String name) =>
        sources.where((item) => item.name == name).firstOrNull?.id;
    final now = today ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);

    Future<Customer> createDemo({
      required String name,
      required String company,
      required String country,
      required String city,
      required String categoryName,
      required String statusName,
      required String sourceName,
      required PriorityLevel priority,
      required DateTime? due,
      required String nextAction,
      required List<String> tagNames,
      FollowUpRecurrence recurrence = FollowUpRecurrence.never,
      String email = '',
      String whatsapp = '',
      String customsInfo = '',
    }) async {
      var customer = await createCustomer(name: name);
      customer = customer.copyWith(
        companyName: company,
        country: country,
        city: city,
        email: email,
        whatsapp: whatsapp,
        customsInfo: customsInfo,
        categoryId: category(categoryName),
        statusId: status(statusName),
        sourceId: source(sourceName),
        priority: priority,
        followUpRecurrence: recurrence,
        nextFollowUpDate: due,
        nextAction: nextAction,
      );
      await saveCustomer(customer);
      final selected = await watchCustomerTags(customer.id).first;
      final ids = selected.map((tag) => tag.id).toSet();
      for (final tagName in tagNames) {
        ids.add((await findOrCreateTag(tagName)).id);
      }
      await setCustomerTags(customer.id, ids);
      return customer;
    }

    final jack = await createDemo(
      name: 'Jack Lim',
      company: 'Manila Home Depot',
      country: 'Philippines',
      city: 'Manila',
      categoryName: 'A级',
      statusName: '意向客户',
      sourceName: 'Alibaba',
      priority: PriorityLevel.high,
      due: day,
      nextAction: '确认最终柜量',
      tagNames: const ['菲律宾', 'WPC', '报价'],
      recurrence: FollowUpRecurrence.weekly,
      email: 'jack@manilahome.example',
      whatsapp: '+63 917 555 0188',
      customsInfo: 'Consignee: Manila Home Depot\nAddress: Quezon City, Metro Manila, Philippines\nTel: +63 917 555 0188\nEmail: jack@manilahome.example',
    );
    final ahmed = await createDemo(
      name: 'Ahmed Hassan',
      company: 'Ahmed Trading',
      country: 'UAE',
      city: 'Dubai',
      categoryName: 'A级',
      statusName: '报价客户',
      sourceName: 'Exhibition',
      priority: PriorityLevel.high,
      due: day,
      nextAction: '确认 WPC Door 最终颜色',
      tagNames: const ['UAE', 'WPC Door', '报价'],
      recurrence: FollowUpRecurrence.biweekly,
      email: 'ahmed@ahmedtrading.example',
      whatsapp: '+971 50 555 9031',
      customsInfo: 'Consignee: Ahmed Trading LLC\nAddress: Al Quoz, Dubai, UAE\nTel: +971 50 555 9031\nEmail: ahmed@ahmedtrading.example',
    );
    final david = await createDemo(
      name: 'David Turner',
      company: 'David Building Materials',
      country: 'UK',
      city: 'London',
      categoryName: 'B级',
      statusName: '样品客户',
      sourceName: 'Google',
      priority: PriorityLevel.medium,
      due: day.add(const Duration(days: 3)),
      nextAction: '等待 Outdoor WPC 样品反馈',
      tagNames: const ['UK', 'Outdoor WPC', '样品'],
      email: 'david@dbmaterials.example',
    );
    final ali = await createDemo(
      name: 'Ali Faisal',
      company: 'Ali Decoration',
      country: 'Saudi Arabia',
      city: 'Riyadh',
      categoryName: 'C级',
      statusName: '待跟进',
      sourceName: 'WhatsApp',
      priority: PriorityLevel.medium,
      due: day.subtract(const Duration(days: 1)),
      nextAction: '补发 PVC Ceiling 包装照片',
      tagNames: const ['Saudi Arabia', 'PVC Ceiling'],
      recurrence: FollowUpRecurrence.monthly,
      whatsapp: '+966 55 230 1188',
    );
    final niran = await createDemo(
      name: 'Niran Chai',
      company: 'Siam Surface Co.',
      country: 'Thailand',
      city: 'Bangkok',
      categoryName: 'B级',
      statusName: '询盘客户',
      sourceName: 'Website',
      priority: PriorityLevel.low,
      due: day.add(const Duration(days: 1)),
      nextAction: '发送 SPC Flooring 装柜方案',
      tagNames: const ['Thailand', 'SPC Flooring'],
    );
    final linh = await createDemo(
      name: 'Linh Nguyen',
      company: 'VietBuild Imports',
      country: 'Vietnam',
      city: 'Ho Chi Minh City',
      categoryName: 'A级',
      statusName: '成交客户',
      sourceName: 'Referral',
      priority: PriorityLevel.high,
      due: day.add(const Duration(days: 5)),
      nextAction: '确认复购订单交期',
      tagNames: const ['Vietnam', 'UV Marble Sheet', '复购'],
    );
    final budi = await createDemo(
      name: 'Budi Santoso',
      company: 'Nusantara Living',
      country: 'Indonesia',
      city: 'Jakarta',
      categoryName: 'D级',
      statusName: '新客户',
      sourceName: 'Facebook',
      priority: PriorityLevel.low,
      due: null,
      nextAction: '了解当地 WPC Panel 尺寸偏好',
      tagNames: const ['Indonesia', 'WPC Panel'],
    );
    final rebecca = await createDemo(
      name: 'Rebecca Stone',
      company: 'Stone Outdoor Ltd',
      country: 'UK',
      city: 'Manchester',
      categoryName: 'B级',
      statusName: '开发中',
      sourceName: 'LinkedIn',
      priority: PriorityLevel.medium,
      due: day.add(const Duration(days: 7)),
      nextAction: '预约下周产品视频会议',
      tagNames: const ['UK', 'Outdoor WPC'],
    );

    await addContact(
      jack.id,
      name: 'Jack Lim',
      role: 'Purchasing Manager',
      email: jack.email,
      whatsapp: jack.whatsapp,
      isPrimary: true,
    );
    await addContact(
      ahmed.id,
      name: 'Sara Mahmoud',
      role: 'Finance',
      email: 'sara@ahmedtrading.example',
    );
    for (final note in const [
      '老板本人负责采购，确认速度快。',
      '对价格敏感，但更重视稳定供货和准时交付。',
      '主要销售 WPC Panel 与 WPC Door。',
    ]) {
      await addNote(jack.id, content: note);
    }
    for (final note in const ['展会认识，项目以别墅和酒店为主。', '颜色确认需要与设计师共同决定。']) {
      await addNote(ahmed.id, content: note);
    }
    for (final note in const ['重视防火证书和英国市场测试报告。', '样品通过后预计先下一个 20GP。']) {
      await addNote(david.id, content: note);
    }

    Future<void> follow(
      Customer customer,
      int daysAgo,
      String channel,
      String content,
      String next,
    ) async {
      await addFollowUp(
        customer.id,
        channel: channel,
        content: content,
        nextAction: next,
        followedUpAt: day.subtract(Duration(days: daysAgo)),
      );
    }

    await follow(jack, 10, 'Email', '发送 WPC 产品目录和检测报告', '确认客户重点产品');
    await follow(jack, 5, 'WhatsApp', '客户确认已经收到报价', '核对首柜产品组合');
    await follow(jack, 2, 'Call', '客户希望先做一个 40HQ', '确认最终柜量');
    await follow(ahmed, 9, 'Meeting', '展会沟通 WPC Door 项目', '发送新颜色样板');
    await follow(ahmed, 3, 'Email', '已发送门板报价和包装方案', '确认 WPC Door 最终颜色');
    await follow(david, 5, 'Email', 'Outdoor WPC 样品已签收', '等待 Outdoor WPC 样品反馈');
    await follow(
      ali,
      6,
      'WhatsApp',
      '客户询问 PVC Ceiling 包装细节',
      '补发 PVC Ceiling 包装照片',
    );

    return [jack, ahmed, david, ali, niran, linh, budi, rebecca];
  }

  @override
  Stream<List<Customer>> watchCustomers(CustomerQuery query) {
    final joined = _db.select(_db.customers).join([
      leftOuterJoin(
        _db.customerTagLinks,
        _db.customerTagLinks.customerId.equalsExp(_db.customers.id),
      ),
      leftOuterJoin(
        _db.customerCategories,
        _db.customerCategories.id.equalsExp(_db.customers.categoryId),
      ),
    ]);
    if (query.projection == CustomerProjection.deleted) {
      joined.where(_db.customers.deletedAt.isNotNull());
    } else {
      joined.where(_db.customers.deletedAt.isNull());
    }
    return joined.watch().map((rows) {
      final customers = <String, Customer>{};
      final tagsByCustomer = <String, Set<String>>{};
      for (final row in rows) {
        final record = row.readTable(_db.customers);
        customers.putIfAbsent(record.id, () => _mapCustomer(record));
        final link = row.readTableOrNull(_db.customerTagLinks);
        if (link != null) {
          tagsByCustomer
              .putIfAbsent(record.id, () => <String>{})
              .add(link.tagId);
        }
      }
      final now = query.today ?? DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final tomorrow = dayStart.add(const Duration(days: 1));
      final upcomingEnd = dayStart.add(const Duration(days: 8));
      final needle = query.search.trim();
      final result = customers.values.where((customer) {
        final projectionMatch = switch (query.projection) {
          CustomerProjection.today =>
            (customer.nextFollowUpDate != null &&
                    customer.nextFollowUpDate!.isBefore(tomorrow)) ||
                customer.followedUpToday(now),
          CustomerProjection.next7Days =>
            customer.nextFollowUpDate != null &&
                !customer.nextFollowUpDate!.isBefore(tomorrow) &&
                customer.nextFollowUpDate!.isBefore(upcomingEnd),
          CustomerProjection.inbox => customer.nextFollowUpDate == null,
          CustomerProjection.category =>
            query.categoryTagId != null &&
                (tagsByCustomer[customer.id] ?? const <String>{}).contains(
                  query.categoryTagId,
                ),
          CustomerProjection.all || CustomerProjection.deleted => true,
        };
        if (!projectionMatch) return false;
        if (needle.isNotEmpty &&
            !FuzzyMatch.matches(needle, [
              customer.name,
              customer.companyName,
              customer.email,
              customer.whatsapp,
              customer.facebook,
            ])) {
          return false;
        }
        final appliedTags = tagsByCustomer[customer.id] ?? const <String>{};
        return query.tagIds.every(appliedTags.contains);
      }).toList();
      result.sort(_customerComparator(query.sort, now));
      return result;
    });
  }

  @override
  Stream<Customer?> watchCustomer(String customerId) =>
      (_db.select(
            _db.customers,
          )..where((row) => row.id.equals(customerId) & row.deletedAt.isNull()))
          .watchSingleOrNull()
          .map((record) => record == null ? null : _mapCustomer(record));

  @override
  Stream<List<CustomerCategory>> watchCategories({
    bool includeInactive = false,
  }) {
    final query = _db.select(_db.customerCategories)
      ..where((row) {
        final active = row.deletedAt.isNull();
        return includeInactive ? active : active & row.isActive.equals(true);
      })
      ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => CustomerCategory(
              id: row.id,
              name: row.name,
              tagId: row.tagId,
              colorValue: row.colorValue,
              isActive: row.isActive,
              sortOrder: row.sortOrder,
            ),
          )
          .toList(),
    );
  }

  @override
  Stream<List<CustomerStatus>> watchStatuses({bool includeInactive = false}) {
    final query = _db.select(_db.customerStatuses)
      ..where((row) {
        final active = row.deletedAt.isNull();
        return includeInactive ? active : active & row.isActive.equals(true);
      })
      ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => CustomerStatus(
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
  Stream<List<CustomerSource>> watchSources({bool includeInactive = false}) {
    final query = _db.select(_db.customerSources)
      ..where((row) {
        final active = row.deletedAt.isNull();
        return includeInactive ? active : active & row.isActive.equals(true);
      })
      ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => CustomerSource(
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
  Stream<List<CustomerContact>> watchContacts(String customerId) =>
      (_db.select(_db.customerContacts)
            ..where(
              (row) =>
                  row.customerId.equals(customerId) & row.deletedAt.isNull(),
            )
            ..orderBy([
              (row) => OrderingTerm.desc(row.isPrimary),
              (row) => OrderingTerm.asc(row.sortOrder),
            ]))
          .watch()
          .map((rows) => rows.map(_mapContact).toList());

  @override
  Stream<List<CustomerFollowUp>> watchFollowUps(
    String customerId, {
    String search = '',
    int limit = 20,
    int offset = 0,
  }) {
    final term = search.trim();
    final query = _db.select(_db.customerFollowUps)
      ..where((row) {
        final active =
            row.customerId.equals(customerId) & row.deletedAt.isNull();
        return active;
      })
      ..orderBy([(row) => OrderingTerm.desc(row.followedUpAt)]);
    if (term.isEmpty) query.limit(limit, offset: offset);
    return query.watch().map((rows) {
      final matches = term.isEmpty
          ? rows
          : rows.where(
              (row) => FuzzyMatch.matches(term, [
                row.content,
                row.nextAction,
                row.channel,
              ]),
            );
      return matches
          .skip(term.isEmpty ? 0 : offset)
          .take(limit)
          .map(_mapFollowUp)
          .toList();
    });
  }

  @override
  Stream<CustomerFollowUp?> watchLatestFollowUp(String customerId) =>
      watchFollowUps(customerId, limit: 1).map((rows) => rows.firstOrNull);

  @override
  Stream<CustomerFollowUp?> watchLatestNextAction(String customerId) {
    final query = _db.select(_db.customerFollowUps)
      ..where(
        (row) =>
            row.customerId.equals(customerId) &
            row.deletedAt.isNull() &
            (row.nextAction.isNotValue('') | row.nextActionType.isNotNull()),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.followedUpAt)])
      ..limit(1);
    return query.watchSingleOrNull().map(
      (record) => record == null ? null : _mapFollowUp(record),
    );
  }

  @override
  Stream<List<CustomerNote>> watchNotes(
    String customerId, {
    String search = '',
    int limit = 20,
    int offset = 0,
  }) {
    final term = search.trim();
    final query = _db.select(_db.customerNotes)
      ..where((row) {
        final active =
            row.customerId.equals(customerId) & row.deletedAt.isNull();
        return active;
      })
      ..orderBy([
        (row) => OrderingTerm.desc(row.createdAt),
        (row) => OrderingTerm.desc(row.sortOrder),
      ]);
    if (term.isEmpty) query.limit(limit, offset: offset);
    return query.watch().map((rows) {
      final matches = term.isEmpty
          ? rows
          : rows.where((row) => FuzzyMatch.matches(term, [row.content]));
      return matches
          .skip(term.isEmpty ? 0 : offset)
          .take(limit)
          .map(_mapNote)
          .toList();
    });
  }

  @override
  Stream<CustomerNote?> watchLatestNote(String customerId) =>
      watchNotes(customerId, limit: 1).map((rows) => rows.firstOrNull);

  @override
  Stream<List<CrmTag>> watchCustomerTags(String customerId) {
    final query =
        _db.select(_db.tags).join([
          innerJoin(
            _db.customerTagLinks,
            _db.customerTagLinks.tagId.equalsExp(_db.tags.id),
          ),
        ])..where(
          _db.customerTagLinks.customerId.equals(customerId) &
              _db.tags.deletedAt.isNull(),
        );
    return query.watch().map(
      (rows) =>
          rows.map((row) => row.readTable(_db.tags)).map(_mapTag).toList(),
    );
  }

  @override
  Stream<List<CrmTag>> watchAllTags() =>
      (_db.select(_db.tags)
            ..where(
              (row) =>
                  row.scope.equals('customer') &
                  row.deletedAt.isNull() &
                  row.isActive.equals(true),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .watch()
          .map((rows) => rows.map(_mapTag).toList());

  @override
  Stream<List<CustomerCustomFieldDefinition>> watchCustomFieldDefinitions() =>
      (_db.select(_db.customerCustomFieldDefinitions)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
          .watch()
          .map((rows) => rows.map(_mapCustomFieldDefinition).toList());

  @override
  Stream<List<CustomerCustomFieldValue>> watchCustomFieldValues(
    String customerId,
  ) =>
      (_db.select(_db.customerCustomFieldValues)..where(
            (row) => row.customerId.equals(customerId) & row.deletedAt.isNull(),
          ))
          .watch()
          .map((rows) => rows.map(_mapCustomFieldValue).toList());

  @override
  Future<Customer> createCustomer({required String name, String? categoryId}) =>
      _db.transaction(() async {
        final trimmed = name.trim();
        if (trimmed.isEmpty) throw ArgumentError.value(name, 'name');
        await _checkUniqueName(trimmed);
        if (categoryId != null) {
          final category =
              await (_db.select(_db.customerCategories)..where(
                    (r) =>
                        r.id.equals(categoryId) &
                        r.deletedAt.isNull() &
                        r.isActive.equals(true),
                  ))
                  .getSingleOrNull();
          if (category == null) throw StateError('客户级别不存在或已停用');
        }
        final now = DateTime.now();
        final customer = Customer(
          id: _uuid.v7(),
          name: trimmed,
          companyName: '',
          country: '',
          city: '',
          address: '',
          website: '',
          whatsapp: '',
          email: '',
          phone: '',
          facebook: '',
          linkedIn: '',
          alibaba: '',
          instagram: '',
          wechat: '',
          customsInfo: '',
          statusId: 'customer-new',
          categoryId: categoryId,
          priority: PriorityLevel.low,
          notes: '',
          nextAction: '',
          sortOrder: now.microsecondsSinceEpoch,
          createdAt: now,
          updatedAt: now,
          version: 1,
        );
        await _db.into(_db.customers).insert(_toCompanion(customer));
        await _syncCategoryTag(customer.id, newCategoryId: categoryId);
        return customer;
      });

  Future<void> _checkUniqueName(String name, {String? excluding}) async {
    final normalized = normalizeCustomerName(name);
    if (normalized.isEmpty) throw ArgumentError.value(name, 'name');
    final rows = await (_db.select(
      _db.customers,
    )..where((r) => r.deletedAt.isNull())).get();
    for (final row in rows) {
      if (row.id != excluding &&
          normalizeCustomerName(row.name) == normalized) {
        throw DuplicateCustomerName(_mapCustomer(row));
      }
    }
  }

  @override
  Future<void> setCustomerSourceText(String customerId, String source) =>
      _db.transaction(() async {
        final current =
            await (_db.select(
                  _db.customers,
                )..where((r) => r.id.equals(customerId) & r.deletedAt.isNull()))
                .getSingle();
        final text = source.trim();
        String? sourceId;
        if (text.isNotEmpty) {
          final sources = await watchSources(includeInactive: true).first;
          sourceId = sources
              .where((s) => s.name.toLowerCase() == text.toLowerCase())
              .firstOrNull
              ?.id;
          sourceId ??= (await createSource(text)).id;
        }
        await (_db.update(
          _db.customers,
        )..where((r) => r.id.equals(customerId))).write(
          CustomersCompanion(
            sourceId: Value(sourceId),
            updatedAt: Value(DateTime.now()),
            version: Value(current.version + 1),
          ),
        );
      });

  @override
  Future<void> saveCustomer(Customer customer) async {
    final current = await (_db.select(
      _db.customers,
    )..where((row) => row.id.equals(customer.id))).getSingleOrNull();
    if (current == null) return;
    final next = customer.copyWith(
      name: customer.name.trim(),
      updatedAt: DateTime.now(),
      version: current.version + 1,
    );
    await _db.transaction(() async {
      if (normalizeCustomerName(current.name) !=
          normalizeCustomerName(next.name)) {
        await _checkUniqueName(next.name, excluding: next.id);
      }
      await (_db.update(
        _db.customers,
      )..where((row) => row.id.equals(next.id))).write(_toCompanion(next));
      if (current.categoryId != next.categoryId) {
        await _syncCategoryTag(
          next.id,
          oldCategoryId: current.categoryId,
          newCategoryId: next.categoryId,
        );
      }
    });
  }

  @override
  Future<void> softDeleteCustomer(String customerId) async {
    final links = await (_db.select(
      _db.customerTagLinks,
    )..where((row) => row.customerId.equals(customerId))).get();
    await (_db.update(
      _db.customers,
    )..where((row) => row.id.equals(customerId))).write(
      CustomersCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await collectUnusedTags(_db, links.map((link) => link.tagId));
  }

  @override
  Future<void> restoreCustomer(String customerId) =>
      (_db.update(
        _db.customers,
      )..where((row) => row.id.equals(customerId))).write(
        CustomersCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<CustomerCategory> createCategory(
    String name, {
    int? colorValue,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name');
    final now = DateTime.now();
    final color = colorValue ?? 0xFFE9EFFB;
    final tag = await findOrCreateTag(trimmed, colorValue: color);
    final category = CustomerCategory(
      id: _uuid.v7(),
      name: trimmed,
      tagId: tag.id,
      colorValue: color,
      isActive: true,
      sortOrder: now.microsecondsSinceEpoch,
    );
    await _db
        .into(_db.customerCategories)
        .insert(
          CustomerCategoriesCompanion.insert(
            id: category.id,
            name: category.name,
            tagId: Value(category.tagId),
            colorValue: Value(category.colorValue),
            sortOrder: category.sortOrder,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return category;
  }

  @override
  Future<void> renameCategory(String categoryId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final category = await (_db.select(
      _db.customerCategories,
    )..where((row) => row.id.equals(categoryId))).getSingleOrNull();
    if (category == null) return;
    await _db.transaction(() async {
      await (_db.update(
        _db.customerCategories,
      )..where((row) => row.id.equals(categoryId))).write(
        CustomerCategoriesCompanion(
          name: Value(trimmed),
          updatedAt: Value(DateTime.now()),
          version: Value(category.version + 1),
        ),
      );
      if (category.tagId != null) {
        await (_db.update(
          _db.tags,
        )..where((row) => row.id.equals(category.tagId!))).write(
          TagsCompanion(name: Value(trimmed), updatedAt: Value(DateTime.now())),
        );
      }
    });
  }

  @override
  Future<void> setCategoryActive(String categoryId, {required bool active}) =>
      (_db.update(
        _db.customerCategories,
      )..where((row) => row.id.equals(categoryId))).write(
        CustomerCategoriesCompanion(
          isActive: Value(active),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> reorderCategories(List<String> orderedIds) =>
      _db.transaction(() async {
        for (var index = 0; index < orderedIds.length; index++) {
          await (_db.update(
            _db.customerCategories,
          )..where((row) => row.id.equals(orderedIds[index]))).write(
            CustomerCategoriesCompanion(
              sortOrder: Value((index + 1) * 1024),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      });

  @override
  Future<CustomerStatus> createStatus(String name, {int? colorValue}) async {
    final now = DateTime.now();
    final status = CustomerStatus(
      id: _uuid.v7(),
      name: name.trim(),
      colorValue: colorValue ?? 0xFF667085,
      isActive: true,
      sortOrder: now.microsecondsSinceEpoch,
    );
    await _db
        .into(_db.customerStatuses)
        .insert(
          CustomerStatusesCompanion.insert(
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
        _db.customerStatuses,
      )..where((row) => row.id.equals(statusId))).write(
        CustomerStatusesCompanion(
          name: Value(name.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> setStatusActive(String statusId, {required bool active}) =>
      (_db.update(
        _db.customerStatuses,
      )..where((row) => row.id.equals(statusId))).write(
        CustomerStatusesCompanion(
          isActive: Value(active),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> setStatusColor(String statusId, int colorValue) =>
      (_db.update(
        _db.customerStatuses,
      )..where((row) => row.id.equals(statusId))).write(
        CustomerStatusesCompanion(
          colorValue: Value(colorValue),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> reorderStatuses(List<String> orderedIds) =>
      _db.transaction(() async {
        for (var index = 0; index < orderedIds.length; index++) {
          await (_db.update(
            _db.customerStatuses,
          )..where((row) => row.id.equals(orderedIds[index]))).write(
            CustomerStatusesCompanion(
              sortOrder: Value((index + 1) * 1024),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      });

  @override
  Future<CustomerSource> createSource(String name, {int? colorValue}) async {
    final now = DateTime.now();
    final source = CustomerSource(
      id: _uuid.v7(),
      name: name.trim(),
      colorValue: colorValue ?? 0xFF667085,
      isActive: true,
      sortOrder: now.microsecondsSinceEpoch,
    );
    await _db
        .into(_db.customerSources)
        .insert(
          CustomerSourcesCompanion.insert(
            id: source.id,
            name: source.name,
            colorValue: Value(source.colorValue),
            sortOrder: source.sortOrder,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return source;
  }

  @override
  Future<void> renameSource(String sourceId, String name) =>
      (_db.update(
        _db.customerSources,
      )..where((row) => row.id.equals(sourceId))).write(
        CustomerSourcesCompanion(
          name: Value(name.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> setSourceActive(String sourceId, {required bool active}) =>
      (_db.update(
        _db.customerSources,
      )..where((row) => row.id.equals(sourceId))).write(
        CustomerSourcesCompanion(
          isActive: Value(active),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> setSourceColor(String sourceId, int colorValue) =>
      (_db.update(
        _db.customerSources,
      )..where((row) => row.id.equals(sourceId))).write(
        CustomerSourcesCompanion(
          colorValue: Value(colorValue),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> reorderSources(List<String> orderedIds) =>
      _db.transaction(() async {
        for (var index = 0; index < orderedIds.length; index++) {
          await (_db.update(
            _db.customerSources,
          )..where((row) => row.id.equals(orderedIds[index]))).write(
            CustomerSourcesCompanion(
              sortOrder: Value((index + 1) * 1024),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      });

  @override
  Future<CrmTag> findOrCreateTag(String name, {int? colorValue}) async {
    final trimmed = name.trim();
    final rows =
        await (_db.select(_db.tags)..where(
              (row) => row.scope.equals('customer') & row.deletedAt.isNull(),
            ))
            .get();
    for (final row in rows) {
      if (row.name.toLowerCase() == trimmed.toLowerCase()) return _mapTag(row);
    }
    final now = DateTime.now();
    final tag = CrmTag(
      id: _uuid.v7(),
      name: trimmed,
      colorValue: colorValue ?? 0xFFE9EFFB,
    );
    await _db
        .into(_db.tags)
        .insert(
          TagsCompanion.insert(
            id: tag.id,
            name: tag.name,
            colorValue: Value(tag.colorValue),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return tag;
  }

  @override
  Future<void> setCustomerTags(
    String customerId,
    Iterable<String> tagIds,
  ) => _db.transaction(() async {
    final previous = await (_db.select(
      _db.customerTagLinks,
    )..where((row) => row.customerId.equals(customerId))).get();
    final allIds = tagIds.toSet();
    final scoped =
        await (_db.select(_db.tags)..where(
              (r) =>
                  r.id.isIn(allIds) &
                  r.scope.equals('customer') &
                  r.deletedAt.isNull(),
            ))
            .get();
    if (scoped.length != allIds.length) {
      throw ArgumentError('Customer tags must belong to the customer scope.');
    }
    final customer = await (_db.select(
      _db.customers,
    )..where((row) => row.id.equals(customerId))).getSingleOrNull();
    if (customer?.categoryId != null) {
      final category =
          await (_db.select(_db.customerCategories)
                ..where((row) => row.id.equals(customer!.categoryId!)))
              .getSingleOrNull();
      if (category?.tagId != null && !allIds.contains(category!.tagId)) {
        await (_db.update(
          _db.customers,
        )..where((row) => row.id.equals(customerId))).write(
          CustomersCompanion(
            categoryId: const Value(null),
            updatedAt: Value(DateTime.now()),
            version: Value(customer!.version + 1),
          ),
        );
      }
    }
    await (_db.delete(
      _db.customerTagLinks,
    )..where((row) => row.customerId.equals(customerId))).go();
    for (final tagId in allIds) {
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
    await collectUnusedTags(
      _db,
      previous.map((link) => link.tagId).where((id) => !allIds.contains(id)),
    );
  });

  @override
  Future<TagReferenceSummary> tagReferences(String tagId) =>
      TagCleanupService(_db).referencesFor(tagId);

  @override
  Future<void> deleteTagDefinition(String tagId) =>
      TagCleanupService(_db).deleteTagDefinition(tagId);

  @override
  Future<CustomerCustomFieldDefinition> createCustomFieldDefinition(
    String name, {
    CustomerCustomFieldType type = CustomerCustomFieldType.text,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name');
    final existing =
        await (_db.select(_db.customerCustomFieldDefinitions)..where(
              (row) =>
                  row.name.lower().equals(trimmed.toLowerCase()) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) return _mapCustomFieldDefinition(existing);
    final now = DateTime.now();
    final definition = CustomerCustomFieldDefinition(
      id: _uuid.v7(),
      name: trimmed,
      type: type,
      sortOrder: now.microsecondsSinceEpoch,
      createdAt: now,
      updatedAt: now,
      version: 1,
    );
    await _db
        .into(_db.customerCustomFieldDefinitions)
        .insert(
          CustomerCustomFieldDefinitionsCompanion.insert(
            id: definition.id,
            name: definition.name,
            type: Value(definition.type.name),
            sortOrder: definition.sortOrder,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return definition;
  }

  @override
  Future<void> setCustomFieldValue(
    String customerId,
    String definitionId,
    String value,
  ) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await (_db.delete(_db.customerCustomFieldValues)..where(
            (row) =>
                row.customerId.equals(customerId) &
                row.definitionId.equals(definitionId),
          ))
          .go();
      return;
    }
    final now = DateTime.now();
    final existing =
        await (_db.select(_db.customerCustomFieldValues)..where(
              (row) =>
                  row.customerId.equals(customerId) &
                  row.definitionId.equals(definitionId),
            ))
            .getSingleOrNull();
    await _db
        .into(_db.customerCustomFieldValues)
        .insertOnConflictUpdate(
          CustomerCustomFieldValuesCompanion.insert(
            customerId: customerId,
            definitionId: definitionId,
            value: Value(trimmed),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            deletedAt: const Value(null),
            version: Value((existing?.version ?? 0) + 1),
          ),
        );
  }

  @override
  Future<int> customFieldValueCount(String definitionId) async {
    final count = _db.customerCustomFieldValues.customerId.count();
    final query = _db.selectOnly(_db.customerCustomFieldValues)
      ..addColumns([count])
      ..where(
        _db.customerCustomFieldValues.definitionId.equals(definitionId) &
            _db.customerCustomFieldValues.deletedAt.isNull(),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }

  @override
  Future<void> deleteCustomFieldDefinition(String definitionId) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(
        _db.customerCustomFieldDefinitions,
      )..where((row) => row.id.equals(definitionId))).write(
        CustomerCustomFieldDefinitionsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await (_db.update(
        _db.customerCustomFieldValues,
      )..where((row) => row.definitionId.equals(definitionId))).write(
        CustomerCustomFieldValuesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<CustomerContact> addContact(
    String customerId, {
    required String name,
    String role = '',
    String email = '',
    String phone = '',
    String whatsapp = '',
    String facebook = '',
    String linkedIn = '',
    String note = '',
    bool isPrimary = false,
  }) async {
    final now = DateTime.now();
    final contact = CustomerContact(
      id: _uuid.v7(),
      customerId: customerId,
      name: name.trim(),
      role: role.trim(),
      email: email.trim(),
      phone: phone.trim(),
      whatsapp: whatsapp.trim(),
      facebook: facebook.trim(),
      linkedIn: linkedIn.trim(),
      note: note.trim(),
      isPrimary: isPrimary,
      sortOrder: now.microsecondsSinceEpoch,
    );
    await _db
        .into(_db.customerContacts)
        .insert(
          CustomerContactsCompanion.insert(
            id: contact.id,
            customerId: customerId,
            name: contact.name,
            role: Value(contact.role),
            email: Value(contact.email),
            phone: Value(contact.phone),
            whatsapp: Value(contact.whatsapp),
            facebook: Value(contact.facebook),
            linkedIn: Value(contact.linkedIn),
            note: Value(contact.note),
            isPrimary: Value(contact.isPrimary),
            sortOrder: contact.sortOrder,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return contact;
  }

  @override
  Future<void> saveContact(CustomerContact contact) =>
      (_db.update(
        _db.customerContacts,
      )..where((row) => row.id.equals(contact.id))).write(
        CustomerContactsCompanion(
          name: Value(contact.name.trim()),
          role: Value(contact.role.trim()),
          email: Value(contact.email.trim()),
          phone: Value(contact.phone.trim()),
          whatsapp: Value(contact.whatsapp.trim()),
          facebook: Value(contact.facebook.trim()),
          linkedIn: Value(contact.linkedIn.trim()),
          note: Value(contact.note.trim()),
          isPrimary: Value(contact.isPrimary),
          sortOrder: Value(contact.sortOrder),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> removeContact(String contactId) =>
      (_db.update(
        _db.customerContacts,
      )..where((row) => row.id.equals(contactId))).write(
        CustomerContactsCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<CustomerNote> addNote(
    String customerId, {
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(content, 'content');
    final existing =
        await (_db.select(_db.customerNotes)..where(
              (row) =>
                  row.customerId.equals(customerId) & row.deletedAt.isNull(),
            ))
            .get();
    const colors = [0xFFE9EFFB, 0xFFF8F1E4, 0xFFEAF4EF, 0xFFF0ECF8, 0xFFF2F3F5];
    final now = DateTime.now();
    final note = CustomerNote(
      id: _uuid.v7(),
      customerId: customerId,
      content: trimmed,
      createdAt: now,
      updatedAt: now,
      colorValue: colors[existing.length % colors.length],
      sortOrder: now.microsecondsSinceEpoch,
      version: 1,
    );
    await _db
        .into(_db.customerNotes)
        .insert(
          CustomerNotesCompanion.insert(
            id: note.id,
            customerId: note.customerId,
            content: Value(note.content),
            colorValue: Value(note.colorValue),
            sortOrder: Value(note.sortOrder),
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
          ),
        );
    return note;
  }

  @override
  Future<void> saveNote(CustomerNote note) async {
    final now = DateTime.now();
    await (_db.update(
      _db.customerNotes,
    )..where((row) => row.id.equals(note.id))).write(
      CustomerNotesCompanion(
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
      (_db.update(
        _db.customerNotes,
      )..where((row) => row.id.equals(noteId))).write(
        CustomerNotesCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<CustomerFollowUp> addFollowUp(
    String customerId, {
    required String channel,
    required String content,
    String nextAction = '',
    NextActionType? nextActionType,
    DateTime? nextFollowUpDate,
    DateTime? followedUpAt,
    bool replaceNextFollowUpDate = false,
  }) async {
    final now = followedUpAt ?? DateTime.now();
    final followUp = CustomerFollowUp(
      id: _uuid.v7(),
      customerId: customerId,
      followedUpAt: now,
      channel: channel,
      content: content.trim(),
      nextAction: nextAction.trim(),
      nextActionType: nextActionType,
      nextFollowUpDate: nextFollowUpDate,
      createdAt: now,
      updatedAt: now,
    );
    await _db.transaction(() async {
      await _db
          .into(_db.customerFollowUps)
          .insert(
            CustomerFollowUpsCompanion.insert(
              id: followUp.id,
              customerId: customerId,
              followedUpAt: now,
              channel: Value(channel),
              content: Value(followUp.content),
              nextAction: Value(followUp.nextAction),
              nextActionType: Value(followUp.nextActionType?.code),
              nextFollowUpDate: Value(nextFollowUpDate),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (_db.update(
        _db.customers,
      )..where((row) => row.id.equals(customerId))).write(
        CustomersCompanion(
          lastFollowUpAt: Value(now),
          nextFollowUpDate: replaceNextFollowUpDate
              ? Value(nextFollowUpDate)
              : nextFollowUpDate == null
              ? const Value.absent()
              : Value(nextFollowUpDate),
          nextAction: followUp.nextAction.isEmpty
              ? followUp.nextActionType == null
                    ? const Value.absent()
                    : const Value('')
              : Value(followUp.nextAction),
          nextActionType: followUp.nextActionType == null
              ? const Value.absent()
              : Value(followUp.nextActionType!.code),
          updatedAt: Value(now),
        ),
      );
    });
    return followUp;
  }

  @override
  Future<void> saveFollowUp(CustomerFollowUp followUp) async {
    final content = followUp.content.trim();
    final nextAction = followUp.nextAction.trim();
    if (content.isEmpty &&
        nextAction.isEmpty &&
        followUp.nextActionType == null) {
      return;
    }
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.customerFollowUps)..where(
            (row) => row.id.equals(followUp.id) & row.deletedAt.isNull(),
          ))
          .write(
            CustomerFollowUpsCompanion(
              channel: Value(followUp.channel),
              content: Value(content),
              nextAction: Value(nextAction),
              nextActionType: Value(followUp.nextActionType?.code),
              nextFollowUpDate: Value(followUp.nextFollowUpDate),
              followedUpAt: Value(followUp.followedUpAt),
              updatedAt: Value(now),
              version: Value(followUp.version + 1),
            ),
          );
      await _refreshCustomerFollowUpSummary(followUp.customerId, now);
    });
  }

  @override
  Future<void> softDeleteFollowUp(String followUpId) async {
    final record =
        await (_db.select(_db.customerFollowUps)..where(
              (row) => row.id.equals(followUpId) & row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (record == null) return;
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(
        _db.customerFollowUps,
      )..where((row) => row.id.equals(followUpId))).write(
        CustomerFollowUpsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          version: Value(record.version + 1),
        ),
      );
      await _refreshCustomerFollowUpSummary(record.customerId, now);
    });
  }

  @override
  Future<CustomerFollowUp> completeTodayFollowUp(
    String customerId, {
    DateTime? now,
  }) => _db.transaction(() async {
    final timestamp = now ?? DateTime.now();
    final customer =
        await (_db.select(_db.customers)..where(
              (row) => row.id.equals(customerId) & row.deletedAt.isNull(),
            ))
            .getSingle();
    final mapped = _mapCustomer(customer);
    final next = _nextFollowUpDate(mapped, timestamp);
    final records = await (_db.select(
      _db.customerFollowUps,
    )..where((r) => r.customerId.equals(customerId))).get();
    final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final existing = records
        .where(
          (r) =>
              r.deletedAt == null &&
              r.origin == 'quickTodayToggle' &&
              r.quickActionDate == day,
        )
        .firstOrNull;
    if (existing != null) return _mapFollowUp(existing);
    final result = await addFollowUp(
      customerId,
      channel: 'Follow-up',
      content: '完成今日跟进',
      nextFollowUpDate: next,
      followedUpAt: timestamp,
      replaceNextFollowUpDate: true,
    );
    await (_db.update(
      _db.customerFollowUps,
    )..where((r) => r.id.equals(result.id))).write(
      CustomerFollowUpsCompanion(
        origin: const Value('quickTodayToggle'),
        quickActionDate: Value(day),
        quickSnapshot: Value(
          jsonEncode({
            'last': customer.lastFollowUpAt?.toIso8601String(),
            'next': customer.nextFollowUpDate?.toIso8601String(),
            'records': records.map((r) => r.id).toList(),
            'versions': {for (final r in records) r.id: r.version},
            'customerVersion': customer.version,
          }),
        ),
      ),
    );
    return result;
  });

  @override
  Future<bool> toggleTodayFollowUp(
    String customerId, {
    DateTime? now,
  }) => _db.transaction(() async {
    final timestamp = now ?? DateTime.now();
    final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final customer =
        await (_db.select(_db.customers)
              ..where((r) => r.id.equals(customerId) & r.deletedAt.isNull()))
            .getSingle();
    final records = await (_db.select(
      _db.customerFollowUps,
    )..where((r) => r.customerId.equals(customerId))).get();
    final action = records
        .where(
          (r) =>
              r.origin == 'quickTodayToggle' &&
              r.quickActionDate == day &&
              r.deletedAt == null,
        )
        .firstOrNull;
    if (action == null && !_mapCustomer(customer).followedUpToday(timestamp)) {
      await completeTodayFollowUp(customerId, now: timestamp);
      return true;
    }
    // A manual completion has no reversible quick action. Never delete it.
    if (action == null || action.quickSnapshot == null || action.version != 1) {
      throw StateError('quickFollowUpUndoUnsafe');
    }
    final snapshot = jsonDecode(action.quickSnapshot!) as Map<String, dynamic>;
    final previousIds = (snapshot['records'] as List).cast<String>().toSet();
    final versions = snapshot['versions'] as Map<String, dynamic>?;
    if (records.any((r) => r.id != action.id && !previousIds.contains(r.id)) ||
        (versions != null &&
            records.any(
              (r) => r.id != action.id && versions[r.id] != r.version,
            )) ||
        (snapshot['customerVersion'] != null &&
            snapshot['customerVersion'] != customer.version) ||
        customer.lastFollowUpAt != action.followedUpAt ||
        customer.nextFollowUpDate != action.nextFollowUpDate ||
        customer.updatedAt.isAfter(action.createdAt)) {
      throw StateError('quickFollowUpUndoUnsafe');
    }
    DateTime? date(String key) =>
        snapshot[key] == null ? null : DateTime.parse(snapshot[key] as String);
    await (_db.update(
      _db.customerFollowUps,
    )..where((r) => r.id.equals(action.id))).write(
      CustomerFollowUpsCompanion(
        deletedAt: Value(timestamp),
        updatedAt: Value(timestamp),
      ),
    );
    await (_db.update(
      _db.customers,
    )..where((r) => r.id.equals(customerId))).write(
      CustomersCompanion(
        lastFollowUpAt: Value(date('last')),
        nextFollowUpDate: Value(date('next')),
        updatedAt: Value(timestamp),
        version: Value(customer.version + 1),
      ),
    );
    return false;
  });

  @override
  Future<List<Customer>> findPotentialDuplicates({
    String email = '',
    String whatsapp = '',
    String phone = '',
    String? excludingCustomerId,
  }) async {
    final emailValue = normalizeEmail(email);
    final whatsappValue = normalizePhone(whatsapp);
    final phoneValue = normalizePhone(phone);
    if (emailValue.isEmpty && whatsappValue.isEmpty && phoneValue.isEmpty) {
      return const [];
    }
    final rows =
        await (_db.select(_db.customers)..where((row) {
              Expression<bool>? match;
              if (emailValue.isNotEmpty) {
                match = row.emailNormalized.equals(emailValue);
              }
              if (whatsappValue.isNotEmpty) {
                final value = row.whatsappNormalized.equals(whatsappValue);
                match = match == null ? value : match | value;
              }
              if (phoneValue.isNotEmpty) {
                final value = row.phoneNormalized.equals(phoneValue);
                match = match == null ? value : match | value;
              }
              var predicate = row.deletedAt.isNull() & match!;
              if (excludingCustomerId != null) {
                predicate =
                    predicate & row.id.equals(excludingCustomerId).not();
              }
              return predicate;
            }))
            .get();
    return rows.map(_mapCustomer).toList();
  }

  Customer _mapCustomer(CustomerRecord row) => Customer(
    id: row.id,
    name: row.name,
    companyName: row.companyName,
    country: row.country,
    city: row.city,
    address: row.address,
    website: row.website,
    whatsapp: row.whatsapp,
    email: row.email,
    phone: row.phone,
    facebook: row.facebook,
    linkedIn: row.linkedIn,
    alibaba: row.alibaba,
    instagram: row.instagram,
    wechat: row.wechat,
    customsInfo: row.customsInfo,
    categoryId: row.categoryId,
    statusId: row.statusId,
    sourceId: row.sourceId,
    priority: PriorityLevel.values.firstWhere(
      (value) => value.name == row.priority,
      orElse: () => PriorityLevel.low,
    ),
    notes: row.notes,
    followUpRecurrence: _recurrenceFromDb(row.followUpRecurrence),
    nextAction: row.nextAction,
    nextActionType: NextActionTypeX.parse(row.nextActionType),
    nextFollowUpDate: row.nextFollowUpDate,
    lastFollowUpAt: row.lastFollowUpAt,
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    version: row.version,
  );

  CustomersCompanion _toCompanion(Customer value) => CustomersCompanion(
    id: Value(value.id),
    name: Value(value.name),
    companyName: Value(value.companyName),
    country: Value(value.country),
    city: Value(value.city),
    address: Value(value.address),
    website: Value(value.website),
    whatsapp: Value(value.whatsapp),
    email: Value(value.email),
    phone: Value(value.phone),
    facebook: Value(value.facebook),
    linkedIn: Value(value.linkedIn),
    alibaba: Value(value.alibaba),
    instagram: Value(value.instagram),
    wechat: Value(value.wechat),
    customsInfo: Value(value.customsInfo),
    emailNormalized: Value(normalizeEmail(value.email)),
    whatsappNormalized: Value(normalizePhone(value.whatsapp)),
    phoneNormalized: Value(normalizePhone(value.phone)),
    categoryId: Value(value.categoryId),
    statusId: Value(value.statusId),
    sourceId: Value(value.sourceId),
    priority: Value(value.priority.name),
    notes: Value(value.notes),
    followUpRecurrence: Value(_recurrenceToDb(value)),
    nextAction: Value(value.nextAction),
    nextActionType: Value(value.nextActionType?.code),
    nextFollowUpDate: Value(value.nextFollowUpDate),
    lastFollowUpAt: Value(value.lastFollowUpAt),
    sortOrder: Value(value.sortOrder),
    createdAt: Value(value.createdAt),
    updatedAt: Value(value.updatedAt),
    deletedAt: Value(value.deletedAt),
    version: Value(value.version),
  );

  CustomerContact _mapContact(CustomerContactRecord row) => CustomerContact(
    id: row.id,
    customerId: row.customerId,
    name: row.name,
    role: row.role,
    email: row.email,
    phone: row.phone,
    whatsapp: row.whatsapp,
    facebook: row.facebook,
    linkedIn: row.linkedIn,
    note: row.note,
    isPrimary: row.isPrimary,
    sortOrder: row.sortOrder,
  );

  CustomerFollowUp _mapFollowUp(CustomerFollowUpRecord row) => CustomerFollowUp(
    id: row.id,
    customerId: row.customerId,
    followedUpAt: row.followedUpAt,
    channel: row.channel,
    content: row.content,
    nextAction: row.nextAction,
    nextActionType: NextActionTypeX.parse(row.nextActionType),
    nextFollowUpDate: row.nextFollowUpDate,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    version: row.version,
  );

  Future<void> _refreshCustomerFollowUpSummary(
    String customerId,
    DateTime updatedAt,
  ) async {
    final latest =
        await (_db.select(_db.customerFollowUps)
              ..where(
                (row) =>
                    row.customerId.equals(customerId) & row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.followedUpAt)])
              ..limit(1))
            .getSingleOrNull();
    final latestAction =
        await (_db.select(_db.customerFollowUps)
              ..where(
                (row) =>
                    row.customerId.equals(customerId) &
                    row.deletedAt.isNull() &
                    (row.nextAction.isNotValue('') |
                        row.nextActionType.isNotNull()),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.followedUpAt)])
              ..limit(1))
            .getSingleOrNull();
    await (_db.update(
      _db.customers,
    )..where((row) => row.id.equals(customerId))).write(
      CustomersCompanion(
        lastFollowUpAt: Value(latest?.followedUpAt),
        nextAction: Value(latestAction?.nextAction ?? ''),
        nextActionType: Value(latestAction?.nextActionType),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  CustomerNote _mapNote(CustomerNoteRecord row) => CustomerNote(
    id: row.id,
    customerId: row.customerId,
    content: row.content,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    colorValue: row.colorValue,
    sortOrder: row.sortOrder,
    deletedAt: row.deletedAt,
    version: row.version,
  );

  CrmTag _mapTag(TagRecord row) =>
      CrmTag(id: row.id, name: row.name, colorValue: row.colorValue);

  CustomerCustomFieldDefinition _mapCustomFieldDefinition(
    CustomerCustomFieldDefinitionRecord row,
  ) => CustomerCustomFieldDefinition(
    id: row.id,
    name: row.name,
    type: CustomerCustomFieldType.values.firstWhere(
      (value) => value.name == row.type,
      orElse: () => CustomerCustomFieldType.text,
    ),
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    version: row.version,
  );

  CustomerCustomFieldValue _mapCustomFieldValue(
    CustomerCustomFieldValueRecord row,
  ) => CustomerCustomFieldValue(
    customerId: row.customerId,
    definitionId: row.definitionId,
    value: row.value,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    version: row.version,
  );

  Future<void> _syncCategoryTag(
    String customerId, {
    String? oldCategoryId,
    String? newCategoryId,
  }) async {
    if (oldCategoryId != null) {
      final old = await (_db.select(
        _db.customerCategories,
      )..where((row) => row.id.equals(oldCategoryId))).getSingleOrNull();
      if (old?.tagId != null) {
        await (_db.delete(_db.customerTagLinks)..where(
              (row) =>
                  row.customerId.equals(customerId) &
                  row.tagId.equals(old!.tagId!),
            ))
            .go();
      }
    }
    if (newCategoryId != null) {
      final next = await (_db.select(
        _db.customerCategories,
      )..where((row) => row.id.equals(newCategoryId))).getSingleOrNull();
      if (next?.tagId != null) {
        await _db
            .into(_db.customerTagLinks)
            .insert(
              CustomerTagLinksCompanion.insert(
                customerId: customerId,
                tagId: next!.tagId!,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }
  }

  Comparator<Customer> _customerComparator(CustomerSort sort, DateTime now) {
    int comparePriority(Customer left, Customer right) =>
        right.priority.index.compareTo(left.priority.index);
    int compareDate(DateTime? left, DateTime? right) {
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    }

    return (left, right) {
      if (sort == CustomerSort.todayDefault) {
        final complete = left
            .followedUpToday(now)
            .index
            .compareTo(right.followedUpToday(now).index);
        if (complete != 0) return complete;
        final priority = comparePriority(left, right);
        if (priority != 0) return priority;
        final due = compareDate(left.nextFollowUpDate, right.nextFollowUpDate);
        if (due != 0) return due;
        return left.sortOrder.compareTo(right.sortOrder);
      }
      return switch (sort) {
        CustomerSort.manual => left.sortOrder.compareTo(right.sortOrder),
        CustomerSort.priority => comparePriority(left, right),
        CustomerSort.nextFollowUp => compareDate(
          left.nextFollowUpDate,
          right.nextFollowUpDate,
        ),
        CustomerSort.lastFollowUp => compareDate(
          right.lastFollowUpAt,
          left.lastFollowUpAt,
        ),
        CustomerSort.createdAt => right.createdAt.compareTo(left.createdAt),
        CustomerSort.name => left.name.toLowerCase().compareTo(
          right.name.toLowerCase(),
        ),
        CustomerSort.todayDefault => 0,
      };
    };
  }

  DateTime? _nextFollowUpDate(Customer customer, DateTime now) {
    return nextCustomerFollowUpDate(
      recurrence: customer.followUpRecurrence,
      now: now,
      scheduledDate: customer.nextFollowUpDate,
    );
  }

  FollowUpRecurrence _recurrenceFromDb(String? value) {
    if (value == null || value.isEmpty) return FollowUpRecurrence.never;
    if (value == 'daily' ||
        value == 'weekdays' ||
        value.startsWith('custom:')) {
      return FollowUpRecurrence.every3Days;
    }
    return FollowUpRecurrence.values.firstWhere(
      (item) => item.name == value,
      orElse: () => FollowUpRecurrence.never,
    );
  }

  String? _recurrenceToDb(Customer customer) =>
      customer.followUpRecurrence == FollowUpRecurrence.never
      ? null
      : customer.followUpRecurrence.name;

  static String normalizeEmail(String value) => value.trim().toLowerCase();

  static String normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}

extension on bool {
  int get index => this ? 1 : 0;
}
