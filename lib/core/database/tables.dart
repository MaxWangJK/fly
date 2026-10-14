import 'package:drift/drift.dart';

@DataClassName('DashboardFocusRecord')
class DashboardFocuses extends Table {
  TextColumn get id => text()();
  TextColumn get focusType => text().unique()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DashboardFocusHistoryRecord')
class DashboardFocusHistories extends Table {
  TextColumn get id => text()();
  TextColumn get focusType => text()();
  TextColumn get content => text()();
  DateTimeColumn get effectiveDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DashboardDailyFocusRecord')
class DashboardDailyFocuses extends Table {
  TextColumn get dayKey => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {dayKey};
}

@DataClassName('DailyReviewRecord')
class DailyReviews extends Table {
  TextColumn get dayKey => text()();
  TextColumn get answersJson => text().withDefault(const Constant('{}'))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {dayKey};
}

@DataClassName('FileFolderRecord')
class FileFolders extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable().references(FileFolders, #id)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get deletionBatch => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FileTagRecord')
class FileTags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get normalizedName => text().unique()();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF81A58F))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class FileTagLinks extends Table {
  TextColumn get fileId => text().references(Attachments, #id)();
  TextColumn get tagId => text().references(FileTags, #id)();
  @override
  Set<Column<Object>> get primaryKey => {fileId, tagId};
}

@DataClassName('NoteFolderRecord')
class NoteFolders extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable().references(NoteFolders, #id)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get deletionBatch => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WorkspaceNoteRecord')
class WorkspaceNotes extends Table {
  IntColumn get manualSortOrder => integer().nullable()();
  TextColumn get id => text()();
  TextColumn get folderId => text().nullable().references(NoteFolders, #id)();
  // Official articles live in signed packs, not in this user-owned table.
  TextColumn get linkedKnowledgeArticleId => text().nullable()();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get deletionBatch => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class KnowledgeFavorites extends Table {
  TextColumn get articleId => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {articleId};
}

@DataClassName('NoteBlockRecord')
class NoteBlocks extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(WorkspaceNotes, #id)();
  TextColumn get type => text()();
  IntColumn get sortOrder => integer()();
  TextColumn get contentJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class NoteTagLinks extends Table {
  TextColumn get noteId =>
      text().references(WorkspaceNotes, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();
  @override
  Set<Column<Object>> get primaryKey => {noteId, tagId};
}

@DataClassName('AppSettingRecord')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('TaskListRecord')
class TaskLists extends Table {
  TextColumn get parentId => text().nullable()();
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF4267E8))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get sortOrder => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TaskRecord')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get priority => text().withDefault(const Constant('none'))();
  BoolColumn get importance => boolean().withDefault(const Constant(false))();
  BoolColumn get urgency => boolean().withDefault(const Constant(false))();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(true))();
  TextColumn get listId =>
      text().withDefault(const Constant('inbox')).references(TaskLists, #id)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get sortOrder => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get recurrenceRule => text().nullable()();
  DateTimeColumn get recurrenceEndAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TagRecord')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get scope => text().withDefault(const Constant('customer'))();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF667085))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {scope, name},
  ];
}

class TaskTags extends Table {
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {taskId, tagId};
}

@DataClassName('ChecklistItemRecord')
class ChecklistItems extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ReminderRecord')
class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get remindAt => dateTime()();
  TextColumn get kind => text().withDefault(const Constant('absolute'))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CustomerCategoryRecord')
class CustomerCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get tagId => text().nullable().references(Tags, #id)();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF667085))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CustomerStatusRecord')
class CustomerStatuses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF667085))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CustomerSourceRecord')
class CustomerSources extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF667085))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CustomerRecord')
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 240)();
  TextColumn get companyName => text().withDefault(const Constant(''))();
  TextColumn get country => text().withDefault(const Constant(''))();
  TextColumn get city => text().withDefault(const Constant(''))();
  TextColumn get address => text().withDefault(const Constant(''))();
  TextColumn get website => text().withDefault(const Constant(''))();
  TextColumn get whatsapp => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get facebook => text().withDefault(const Constant(''))();
  TextColumn get linkedIn => text().withDefault(const Constant(''))();
  TextColumn get alibaba => text().withDefault(const Constant(''))();
  TextColumn get instagram => text().withDefault(const Constant(''))();
  TextColumn get wechat => text().withDefault(const Constant(''))();
  TextColumn get customsInfo => text().withDefault(const Constant(''))();
  TextColumn get emailNormalized => text().withDefault(const Constant(''))();
  TextColumn get whatsappNormalized => text().withDefault(const Constant(''))();
  TextColumn get phoneNormalized => text().withDefault(const Constant(''))();
  TextColumn get categoryId =>
      text().nullable().references(CustomerCategories, #id)();
  TextColumn get statusId =>
      text().nullable().references(CustomerStatuses, #id)();
  TextColumn get sourceId =>
      text().nullable().references(CustomerSources, #id)();
  TextColumn get priority => text().withDefault(const Constant('low'))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get followUpRecurrence => text().nullable()();
  TextColumn get nextAction => text().withDefault(const Constant(''))();
  TextColumn get nextActionType => text().nullable()();
  DateTimeColumn get nextFollowUpDate => dateTime().nullable()();
  DateTimeColumn get lastFollowUpAt => dateTime().nullable()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CustomerContactRecord')
class CustomerContacts extends Table {
  TextColumn get id => text()();
  TextColumn get customerId =>
      text().references(Customers, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 240)();
  TextColumn get role => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get whatsapp => text().withDefault(const Constant(''))();
  TextColumn get facebook => text().withDefault(const Constant(''))();
  TextColumn get linkedIn => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CustomerNoteRecord')
class CustomerNotes extends Table {
  TextColumn get id => text()();
  TextColumn get customerId =>
      text().references(Customers, #id, onDelete: KeyAction.cascade)();
  TextColumn get content => text().withDefault(const Constant(''))();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFFE9EFFB))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CustomerCustomFieldDefinitionRecord')
class CustomerCustomFieldDefinitions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get type => text().withDefault(const Constant('text'))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CustomerCustomFieldValueRecord')
class CustomerCustomFieldValues extends Table {
  TextColumn get customerId =>
      text().references(Customers, #id, onDelete: KeyAction.cascade)();
  TextColumn get definitionId => text().references(
    CustomerCustomFieldDefinitions,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get value => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {customerId, definitionId};
}

@DataClassName('CustomerFollowUpRecord')
class CustomerFollowUps extends Table {
  TextColumn get id => text()();
  TextColumn get origin => text().withDefault(const Constant('manual'))();
  DateTimeColumn get quickActionDate => dateTime().nullable()();
  TextColumn get quickSnapshot => text().nullable()();
  TextColumn get customerId =>
      text().references(Customers, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get followedUpAt => dateTime()();
  TextColumn get channel => text().withDefault(const Constant('WhatsApp'))();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get nextAction => text().withDefault(const Constant(''))();
  TextColumn get nextActionType => text().nullable()();
  DateTimeColumn get nextFollowUpDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CustomerTagLinks extends Table {
  TextColumn get customerId =>
      text().references(Customers, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {customerId, tagId};
}

@DataClassName('OrderStatusRecord')
class OrderStatuses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF667085))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('OrderRecord')
class Orders extends Table {
  TextColumn get id => text()();
  TextColumn get orderNumber => text().withLength(min: 1, max: 120)();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get statusId => text().nullable().references(OrderStatuses, #id)();
  TextColumn get priority => text().withDefault(const Constant('low'))();
  BoolColumn get importance => boolean().withDefault(const Constant(false))();
  BoolColumn get urgency => boolean().withDefault(const Constant(false))();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get baseProfitCurrency =>
      text().withDefault(const Constant('CNY'))();
  IntColumn get exchangeRateMicros =>
      integer().withDefault(const Constant(0))();
  IntColumn get salesAmount => integer().withDefault(const Constant(0))();
  IntColumn get taxRefund => integer().withDefault(const Constant(0))();
  TextColumn get taxRefundCurrency =>
      text().withDefault(const Constant('CNY'))();
  IntColumn get inlandCost => integer().withDefault(const Constant(0))();
  IntColumn get portCharges => integer().withDefault(const Constant(0))();
  IntColumn get otherCost => integer().withDefault(const Constant(0))();
  IntColumn get otherIncome => integer().withDefault(const Constant(0))();
  DateTimeColumn get orderDate => dateTime().nullable()();
  DateTimeColumn get deliveryDate => dateTime().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {orderNumber},
  ];
}

@DataClassName('OrderNoteRecord')
class OrderNotes extends Table {
  TextColumn get id => text()();
  TextColumn get orderId =>
      text().references(Orders, #id, onDelete: KeyAction.cascade)();
  TextColumn get content => text().withDefault(const Constant(''))();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFFE9EFFB))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FactoryRecord')
class Factories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 240)();
  TextColumn get contact => text().withDefault(const Constant(''))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get address => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFFE9EFFB))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ProductRecord')
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 240)();
  TextColumn get unit => text().withDefault(const Constant('pcs'))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('OrderProductionItemRecord')
class OrderProductionItems extends Table {
  TextColumn get id => text()();
  TextColumn get orderId =>
      text().references(Orders, #id, onDelete: KeyAction.cascade)();
  TextColumn get factoryId => text().nullable().references(Factories, #id)();
  TextColumn get productId => text().nullable().references(Products, #id)();
  IntColumn get quantityMilli => integer().withDefault(const Constant(1000))();
  TextColumn get unit => text().withDefault(const Constant('pcs'))();
  IntColumn get unitPrice => integer().withDefault(const Constant(0))();
  IntColumn get salesAmount => integer().withDefault(const Constant(0))();
  IntColumn get factoryCost => integer().withDefault(const Constant(0))();
  TextColumn get factoryCostCurrency =>
      text().withDefault(const Constant('CNY'))();
  TextColumn get productionStatus =>
      text().withDefault(const Constant('pending'))();
  TextColumn get factoryOrderStatus =>
      text().withDefault(const Constant('notPlaced'))();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFFE9EFFB))();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('OrderPaymentRecord')
class OrderPayments extends Table {
  TextColumn get id => text()();
  TextColumn get orderId =>
      text().references(Orders, #id, onDelete: KeyAction.cascade)();
  IntColumn get amount => integer()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get paymentType => text().withDefault(const Constant('deposit'))();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get method => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get attachmentId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('OrderCostEntryRecord')
class OrderCostEntries extends Table {
  TextColumn get id => text()();
  TextColumn get orderId =>
      text().references(Orders, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get costType => text().withDefault(const Constant('其他'))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get attachmentId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class OrderTagLinks extends Table {
  TextColumn get orderId =>
      text().references(Orders, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {orderId, tagId};
}

@DataClassName('OrderFileRecord')
class OrderFiles extends Table {
  TextColumn get id => text()();
  TextColumn get orderId =>
      text().references(Orders, #id, onDelete: KeyAction.cascade)();
  TextColumn get paymentId =>
      text().nullable().references(OrderPayments, #id)();
  TextColumn get fileName => text()();
  TextColumn get originalName => text()();
  TextColumn get documentType => text().withDefault(const Constant('Other'))();
  TextColumn get localRelativePath => text()();
  IntColumn get fileSize => integer()();
  TextColumn get mimeType => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AttachmentRecord')
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get folderId => text().nullable().references(FileFolders, #id)();
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get sha256 => text().nullable()();
  TextColumn get thumbnailRelativePath => text().nullable()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  TextColumn get deletionBatch => text().nullable()();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();
  TextColumn get fileName => text()();
  TextColumn get originalName => text()();
  TextColumn get relativePath => text()();
  TextColumn get mimeType => text().withDefault(const Constant(''))();
  IntColumn get fileSize => integer()();
  TextColumn get documentType => text().withDefault(const Constant('Other'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('NotificationDeliveryLogRecord')
class NotificationDeliveryLogs extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get scheduledTime => dateTime()();
  DateTimeColumn get deliveredAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {entityType, entityId, scheduledTime},
  ];
}

@DataClassName('ContainerPresetRecord')
class ContainerPresets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get innerLengthMm => integer()();
  IntColumn get innerWidthMm => integer()();
  IntColumn get innerHeightMm => integer()();
  IntColumn get doorWidthMm => integer().nullable()();
  IntColumn get doorHeightMm => integer().nullable()();
  IntColumn get maxPayloadGrams => integer()();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF718096))();
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CargoPackageRecord')
class CargoPackages extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get type => text().withDefault(const Constant('package'))();
  IntColumn get lengthMm => integer()();
  IntColumn get widthMm => integer()();
  IntColumn get heightMm => integer()();
  IntColumn get weightGrams => integer()();
  IntColumn get defaultSectionQuantity => integer().nullable()();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF7FA7C9))();
  BoolColumn get allowRotateX => boolean().withDefault(const Constant(true))();
  BoolColumn get allowRotateY => boolean().withDefault(const Constant(true))();
  BoolColumn get allowRotateZ => boolean().withDefault(const Constant(true))();
  BoolColumn get stackable => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LoadingPlanRecord')
class LoadingPlans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get containerPresetId =>
      text().references(ContainerPresets, #id)();
  IntColumn get maxPayloadGrams => integer()();
  IntColumn get clearanceMm => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LoadingPlanGroupRecord')
class LoadingPlanGroups extends Table {
  TextColumn get id => text()();
  TextColumn get planId =>
      text().references(LoadingPlans, #id, onDelete: KeyAction.cascade)();
  TextColumn get cargoPackageId => text().references(CargoPackages, #id)();
  TextColumn get sectionId => text().nullable()();
  TextColumn get entryId => text().nullable()();
  BoolColumn get needsReview => boolean().withDefault(const Constant(false))();
  BoolColumn get allowStack => boolean().withDefault(const Constant(true))();
  IntColumn get quantity => integer()();
  IntColumn get rows => integer()();
  IntColumn get columns => integer()();
  IntColumn get layers => integer()();
  IntColumn get emptySlots => integer().withDefault(const Constant(0))();
  IntColumn get boundingLengthMm => integer()();
  IntColumn get boundingWidthMm => integer()();
  IntColumn get boundingHeightMm => integer()();
  IntColumn get positionXmm => integer().withDefault(const Constant(0))();
  IntColumn get positionYmm => integer().withDefault(const Constant(0))();
  IntColumn get positionZmm => integer().withDefault(const Constant(0))();
  IntColumn get rotationX => integer().withDefault(const Constant(0))();
  IntColumn get rotationY => integer().withDefault(const Constant(0))();
  IntColumn get rotationZ => integer().withDefault(const Constant(0))();
  IntColumn get colorValue => integer()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ContainerSectionRecord')
class ContainerSections extends Table {
  TextColumn get id => text()();
  TextColumn get planId =>
      text().references(LoadingPlans, #id, onDelete: KeyAction.cascade)();
  IntColumn get sectionIndex => integer()();
  TextColumn get name => text()();
  IntColumn get startXmm => integer()();
  IntColumn get lengthMm => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SectionCargoEntryRecord')
class SectionCargoEntries extends Table {
  TextColumn get id => text()();
  TextColumn get sectionId =>
      text().references(ContainerSections, #id, onDelete: KeyAction.cascade)();
  TextColumn get cargoPackageId => text().references(CargoPackages, #id)();
  TextColumn get cargoSnapshot => text()();
  IntColumn get quantity => integer()();
  TextColumn get orientation => text().withDefault(const Constant('flat'))();
  BoolColumn get placeOnBottom =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get allowStack => boolean().withDefault(const Constant(true))();
  TextColumn get horizontalPlacement =>
      text().withDefault(const Constant('automatic'))();
  BoolColumn get manualQuantityOverride =>
      boolean().withDefault(const Constant(false))();
  IntColumn get colorOverride => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}
