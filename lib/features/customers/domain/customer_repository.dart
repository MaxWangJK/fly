import '../../../shared/domain/tag_lifecycle.dart';
import 'customer.dart';

abstract interface class CustomerRepository {
  Stream<List<Customer>> watchCustomers(CustomerQuery query);
  Stream<Customer?> watchCustomer(String customerId);
  Stream<List<CustomerCategory>> watchCategories({
    bool includeInactive = false,
  });
  Stream<List<CustomerStatus>> watchStatuses({bool includeInactive = false});
  Stream<List<CustomerSource>> watchSources({bool includeInactive = false});
  Stream<List<CustomerContact>> watchContacts(String customerId);
  Stream<List<CustomerFollowUp>> watchFollowUps(
    String customerId, {
    String search = '',
    int limit = 20,
    int offset = 0,
  });
  Stream<CustomerFollowUp?> watchLatestFollowUp(String customerId);
  Stream<CustomerFollowUp?> watchLatestNextAction(String customerId);
  Stream<List<CustomerNote>> watchNotes(
    String customerId, {
    String search = '',
    int limit = 20,
    int offset = 0,
  });
  Stream<CustomerNote?> watchLatestNote(String customerId);
  Stream<List<CrmTag>> watchCustomerTags(String customerId);
  Stream<List<CrmTag>> watchAllTags();
  Stream<List<CustomerCustomFieldDefinition>> watchCustomFieldDefinitions();
  Stream<List<CustomerCustomFieldValue>> watchCustomFieldValues(
    String customerId,
  );

  Future<Customer> createCustomer({
    required String name,
    String? categoryId,
    String country = '',
    String? statusId,
    String source = '',
  });
  Future<void> setCustomerSourceText(String customerId, String source);
  Future<void> saveCustomer(Customer customer);
  Future<void> softDeleteCustomer(String customerId);
  Future<void> restoreCustomer(String customerId);

  Future<CustomerCategory> createCategory(String name, {int? colorValue});
  Future<void> renameCategory(String categoryId, String name);
  Future<void> setCategoryActive(String categoryId, {required bool active});
  Future<void> reorderCategories(List<String> orderedIds);

  Future<CustomerStatus> createStatus(String name, {int? colorValue});
  Future<void> renameStatus(String statusId, String name);
  Future<void> setStatusActive(String statusId, {required bool active});
  Future<void> setStatusColor(String statusId, int colorValue);
  Future<void> reorderStatuses(List<String> orderedIds);

  Future<CustomerSource> createSource(String name, {int? colorValue});
  Future<void> renameSource(String sourceId, String name);
  Future<void> setSourceActive(String sourceId, {required bool active});
  Future<void> setSourceColor(String sourceId, int colorValue);
  Future<void> reorderSources(List<String> orderedIds);

  Future<CrmTag> findOrCreateTag(String name, {int? colorValue});
  Future<void> setCustomerTags(String customerId, Iterable<String> tagIds);
  Future<TagReferenceSummary> tagReferences(String tagId);
  Future<void> deleteTagDefinition(String tagId);

  Future<CustomerCustomFieldDefinition> createCustomFieldDefinition(
    String name, {
    CustomerCustomFieldType type,
  });
  Future<void> setCustomFieldValue(
    String customerId,
    String definitionId,
    String value,
  );
  Future<int> customFieldValueCount(String definitionId);
  Future<void> deleteCustomFieldDefinition(String definitionId);

  Future<CustomerContact> addContact(
    String customerId, {
    required String name,
    String role,
    String email,
    String phone,
    String whatsapp,
    String facebook,
    String linkedIn,
    String note,
    bool isPrimary,
  });
  Future<void> saveContact(CustomerContact contact);
  Future<void> removeContact(String contactId);

  Future<CustomerNote> addNote(String customerId, {required String content});
  Future<void> saveNote(CustomerNote note);
  Future<void> softDeleteNote(String noteId);

  Future<CustomerFollowUp> addFollowUp(
    String customerId, {
    required String channel,
    required String content,
    String nextAction,
    NextActionType? nextActionType,
    DateTime? nextFollowUpDate,
    DateTime? followedUpAt,
    bool replaceNextFollowUpDate = false,
  });
  Future<void> saveFollowUp(CustomerFollowUp followUp);
  Future<void> softDeleteFollowUp(String followUpId);
  Future<CustomerFollowUp> completeTodayFollowUp(
    String customerId, {
    DateTime? now,
  });

  /// Returns true for completion, false for undo. Unsafe undo throws.
  Future<bool> toggleTodayFollowUp(String customerId, {DateTime? now});

  Future<List<Customer>> findPotentialDuplicates({
    String email,
    String whatsapp,
    String phone,
    String? excludingCustomerId,
  });
}
