import '../../../shared/domain/priority.dart';

enum FollowUpRecurrence {
  never,
  every3Days,
  weekly,
  biweekly,
  monthly,
  every2Months,
}

DateTime? nextCustomerFollowUpDate({
  required FollowUpRecurrence recurrence,
  required DateTime now,
  DateTime? scheduledDate,
}) {
  if (recurrence == FollowUpRecurrence.never) return null;
  final today = DateTime(now.year, now.month, now.day);
  final scheduled = scheduledDate;
  final base = scheduled == null
      ? today
      : DateTime(scheduled.year, scheduled.month, scheduled.day);
  return switch (recurrence) {
    FollowUpRecurrence.never => null,
    FollowUpRecurrence.every3Days => base.add(const Duration(days: 3)),
    FollowUpRecurrence.weekly => base.add(const Duration(days: 7)),
    FollowUpRecurrence.biweekly => base.add(const Duration(days: 14)),
    FollowUpRecurrence.monthly => _addCalendarMonths(base, 1),
    FollowUpRecurrence.every2Months => _addCalendarMonths(base, 2),
  };
}

DateTime _addCalendarMonths(DateTime value, int months) {
  final firstOfFollowingMonth = DateTime(value.year, value.month + months + 1);
  final lastDayOfTargetMonth = firstOfFollowingMonth.subtract(
    const Duration(days: 1),
  );
  final day = value.day > lastDayOfTargetMonth.day
      ? lastDayOfTargetMonth.day
      : value.day;
  return DateTime(value.year, value.month + months, day);
}

enum CustomerProjection { today, next7Days, inbox, category, all, deleted }

enum CustomerSort {
  todayDefault,
  manual,
  priority,
  nextFollowUp,
  lastFollowUp,
  createdAt,
  name,
}

enum NextActionType {
  waitingReply,
  sendQuote,
  sendSample,
  paymentFollowUp,
  contactAgain,
  confirmOrder,
  other,
}

extension NextActionTypeX on NextActionType {
  String get code => switch (this) {
    NextActionType.waitingReply => 'waiting_reply',
    NextActionType.sendQuote => 'send_quote',
    NextActionType.sendSample => 'send_sample',
    NextActionType.paymentFollowUp => 'payment_followup',
    NextActionType.contactAgain => 'contact_again',
    NextActionType.confirmOrder => 'confirm_order',
    NextActionType.other => 'other',
  };

  String get label => switch (this) {
    NextActionType.waitingReply => '等客户回复',
    NextActionType.sendQuote => '发报价',
    NextActionType.sendSample => '寄样',
    NextActionType.paymentFollowUp => '催付款',
    NextActionType.contactAgain => '再联系',
    NextActionType.confirmOrder => '确认订单',
    NextActionType.other => '其它',
  };

  static NextActionType? parse(String? value) {
    if (value == null || value.isEmpty) return null;
    return NextActionType.values.cast<NextActionType?>().firstWhere(
      (item) => item?.code == value,
      orElse: () => null,
    );
  }
}

class CustomerQuery {
  const CustomerQuery({
    required this.projection,
    this.categoryId,
    this.categoryTagId,
    this.search = '',
    this.tagIds = const {},
    this.sort = CustomerSort.todayDefault,
    this.today,
  });

  final CustomerProjection projection;
  final String? categoryId;
  final String? categoryTagId;
  final String search;
  final Set<String> tagIds;
  final CustomerSort sort;
  final DateTime? today;

  CustomerQuery copyWith({
    CustomerProjection? projection,
    String? categoryId,
    String? categoryTagId,
    String? search,
    Set<String>? tagIds,
    CustomerSort? sort,
    DateTime? today,
  }) => CustomerQuery(
    projection: projection ?? this.projection,
    categoryId: categoryId ?? this.categoryId,
    categoryTagId: categoryTagId ?? this.categoryTagId,
    search: search ?? this.search,
    tagIds: tagIds ?? this.tagIds,
    sort: sort ?? this.sort,
    today: today ?? this.today,
  );
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.companyName,
    required this.country,
    required this.city,
    required this.address,
    required this.website,
    required this.whatsapp,
    required this.email,
    required this.phone,
    required this.facebook,
    required this.linkedIn,
    required this.alibaba,
    required this.instagram,
    required this.wechat,
    this.customsInfo = '',
    required this.priority,
    required this.notes,
    required this.nextAction,
    this.nextActionType,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.categoryId,
    this.statusId,
    this.sourceId,
    this.followUpRecurrence = FollowUpRecurrence.never,
    this.nextFollowUpDate,
    this.lastFollowUpAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String companyName;
  final String country;
  final String city;
  final String address;
  final String website;
  final String whatsapp;
  final String email;
  final String phone;
  final String facebook;
  final String linkedIn;
  final String alibaba;
  final String instagram;
  final String wechat;
  final String customsInfo;
  final String? categoryId;
  final String? statusId;
  final String? sourceId;
  final PriorityLevel priority;
  final String notes;
  final FollowUpRecurrence followUpRecurrence;
  final String nextAction;
  final NextActionType? nextActionType;
  final DateTime? nextFollowUpDate;
  final DateTime? lastFollowUpAt;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  bool followedUpToday(DateTime now) =>
      lastFollowUpAt != null && _sameDate(lastFollowUpAt!, now);

  Customer copyWith({
    String? id,
    String? name,
    String? companyName,
    String? country,
    String? city,
    String? address,
    String? website,
    String? whatsapp,
    String? email,
    String? phone,
    String? facebook,
    String? linkedIn,
    String? alibaba,
    String? instagram,
    String? wechat,
    String? customsInfo,
    Object? categoryId = _unset,
    Object? statusId = _unset,
    Object? sourceId = _unset,
    PriorityLevel? priority,
    String? notes,
    FollowUpRecurrence? followUpRecurrence,
    String? nextAction,
    Object? nextActionType = _unset,
    Object? nextFollowUpDate = _unset,
    Object? lastFollowUpAt = _unset,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    int? version,
  }) => Customer(
    id: id ?? this.id,
    name: name ?? this.name,
    companyName: companyName ?? this.companyName,
    country: country ?? this.country,
    city: city ?? this.city,
    address: address ?? this.address,
    website: website ?? this.website,
    whatsapp: whatsapp ?? this.whatsapp,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    facebook: facebook ?? this.facebook,
    linkedIn: linkedIn ?? this.linkedIn,
    alibaba: alibaba ?? this.alibaba,
    instagram: instagram ?? this.instagram,
    wechat: wechat ?? this.wechat,
    customsInfo: customsInfo ?? this.customsInfo,
    categoryId: identical(categoryId, _unset)
        ? this.categoryId
        : categoryId as String?,
    statusId: identical(statusId, _unset) ? this.statusId : statusId as String?,
    sourceId: identical(sourceId, _unset) ? this.sourceId : sourceId as String?,
    priority: priority ?? this.priority,
    notes: notes ?? this.notes,
    followUpRecurrence: followUpRecurrence ?? this.followUpRecurrence,
    nextAction: nextAction ?? this.nextAction,
    nextActionType: identical(nextActionType, _unset)
        ? this.nextActionType
        : nextActionType as NextActionType?,
    nextFollowUpDate: identical(nextFollowUpDate, _unset)
        ? this.nextFollowUpDate
        : nextFollowUpDate as DateTime?,
    lastFollowUpAt: identical(lastFollowUpAt, _unset)
        ? this.lastFollowUpAt
        : lastFollowUpAt as DateTime?,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: identical(deletedAt, _unset)
        ? this.deletedAt
        : deletedAt as DateTime?,
    version: version ?? this.version,
  );
}

class CustomerCategory {
  const CustomerCategory({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.isActive,
    required this.sortOrder,
    this.tagId,
  });

  final String id;
  final String name;
  final String? tagId;
  final int colorValue;
  final bool isActive;
  final int sortOrder;
}

class CustomerStatus {
  const CustomerStatus({
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

class CustomerSource {
  const CustomerSource({
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

class CrmTag {
  const CrmTag({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  final String id;
  final String name;
  final int colorValue;
}

class CustomerContact {
  const CustomerContact({
    required this.id,
    required this.customerId,
    required this.name,
    required this.role,
    required this.email,
    required this.phone,
    required this.whatsapp,
    required this.facebook,
    required this.linkedIn,
    required this.note,
    required this.isPrimary,
    required this.sortOrder,
  });

  final String id;
  final String customerId;
  final String name;
  final String role;
  final String email;
  final String phone;
  final String whatsapp;
  final String facebook;
  final String linkedIn;
  final String note;
  final bool isPrimary;
  final int sortOrder;
}

class CustomerFollowUp {
  const CustomerFollowUp({
    required this.id,
    required this.customerId,
    required this.followedUpAt,
    required this.channel,
    required this.content,
    required this.nextAction,
    this.nextActionType,
    required this.createdAt,
    required this.updatedAt,
    this.nextFollowUpDate,
    this.deletedAt,
    this.version = 1,
  });

  final String id;
  final String customerId;
  final DateTime followedUpAt;
  final String channel;
  final String content;
  final String nextAction;
  final NextActionType? nextActionType;
  final DateTime? nextFollowUpDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  CustomerFollowUp copyWith({
    String? channel,
    String? content,
    String? nextAction,
    Object? nextActionType = _unset,
    Object? nextFollowUpDate = _unset,
    DateTime? followedUpAt,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    int? version,
  }) => CustomerFollowUp(
    id: id,
    customerId: customerId,
    followedUpAt: followedUpAt ?? this.followedUpAt,
    channel: channel ?? this.channel,
    content: content ?? this.content,
    nextAction: nextAction ?? this.nextAction,
    nextActionType: identical(nextActionType, _unset)
        ? this.nextActionType
        : nextActionType as NextActionType?,
    nextFollowUpDate: identical(nextFollowUpDate, _unset)
        ? this.nextFollowUpDate
        : nextFollowUpDate as DateTime?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: identical(deletedAt, _unset)
        ? this.deletedAt
        : deletedAt as DateTime?,
    version: version ?? this.version,
  );
}

class CustomerNote {
  const CustomerNote({
    required this.id,
    required this.customerId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.colorValue,
    required this.sortOrder,
    required this.version,
    this.deletedAt,
  });

  final String id;
  final String customerId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int colorValue;
  final int sortOrder;
  final DateTime? deletedAt;
  final int version;

  CustomerNote copyWith({
    String? content,
    DateTime? updatedAt,
    int? colorValue,
    int? sortOrder,
    DateTime? deletedAt,
    int? version,
  }) => CustomerNote(
    id: id,
    customerId: customerId,
    content: content ?? this.content,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    colorValue: colorValue ?? this.colorValue,
    sortOrder: sortOrder ?? this.sortOrder,
    deletedAt: deletedAt ?? this.deletedAt,
    version: version ?? this.version,
  );
}

enum CustomerCustomFieldType { text, number, date }

class CustomerCustomFieldDefinition {
  const CustomerCustomFieldDefinition({
    required this.id,
    required this.name,
    required this.type,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.deletedAt,
  });

  final String id;
  final String name;
  final CustomerCustomFieldType type;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
}

class CustomerCustomFieldValue {
  const CustomerCustomFieldValue({
    required this.customerId,
    required this.definitionId,
    required this.value,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.deletedAt,
  });

  final String customerId;
  final String definitionId;
  final String value;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

class _Unset {
  const _Unset();
}

const _unset = _Unset();
