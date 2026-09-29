import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tasks/presentation/task_providers.dart';
import '../data/drift_customer_repository.dart';
import '../domain/customer.dart';
import '../domain/customer_repository.dart';

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => DriftCustomerRepository(ref.watch(databaseProvider)),
);

final selectedCustomerIdProvider = StateProvider<String?>((ref) => null);

enum DetailExtensionType { none, notes, followUps }

final customerDetailExtensionProvider = StateProvider<DetailExtensionType>(
  (ref) => DetailExtensionType.none,
);
final customerSearchProvider = StateProvider<String>((ref) => '');
final customerTagFilterProvider = StateProvider<Set<String>>((ref) => {});
final customerSortProvider = StateProvider<CustomerSort>(
  (ref) => CustomerSort.todayDefault,
);

final customersProvider = StreamProvider.family<List<Customer>, CustomerQuery>(
  (ref, query) => ref.watch(customerRepositoryProvider).watchCustomers(query),
);
final customerListProvider =
    StreamProvider.family<
      List<Customer>,
      ({CustomerProjection projection, String? categoryId})
    >((ref, route) {
      final query = CustomerQuery(
        projection: route.projection,
        categoryId: route.categoryId,
        categoryTagId: ref
            .watch(customerCategoriesProvider)
            .valueOrNull
            ?.where((category) => category.id == route.categoryId)
            .firstOrNull
            ?.tagId,
        search: ref.watch(customerSearchProvider),
        tagIds: ref.watch(customerTagFilterProvider),
        sort: ref.watch(customerSortProvider),
      );
      return ref.watch(customerRepositoryProvider).watchCustomers(query);
    });
final allCustomersProvider = StreamProvider<List<Customer>>(
  (ref) => ref
      .watch(customerRepositoryProvider)
      .watchCustomers(const CustomerQuery(projection: CustomerProjection.all)),
);
final customerProvider = StreamProvider.family<Customer?, String>(
  (ref, id) => ref.watch(customerRepositoryProvider).watchCustomer(id),
);
final customerCategoriesProvider = StreamProvider<List<CustomerCategory>>(
  (ref) => ref.watch(customerRepositoryProvider).watchCategories(),
);
final customerStatusesProvider = StreamProvider<List<CustomerStatus>>(
  (ref) => ref.watch(customerRepositoryProvider).watchStatuses(),
);
final allCustomerStatusesProvider = StreamProvider<List<CustomerStatus>>(
  (ref) => ref
      .watch(customerRepositoryProvider)
      .watchStatuses(includeInactive: true),
);
final customerSourcesProvider = StreamProvider<List<CustomerSource>>(
  (ref) => ref.watch(customerRepositoryProvider).watchSources(),
);
final allCustomerSourcesProvider = StreamProvider<List<CustomerSource>>(
  (ref) =>
      ref.watch(customerRepositoryProvider).watchSources(includeInactive: true),
);
final allCrmTagsProvider = StreamProvider<List<CrmTag>>(
  (ref) => ref.watch(customerRepositoryProvider).watchAllTags(),
);
final customerTagsProvider = StreamProvider.family<List<CrmTag>, String>(
  (ref, id) => ref.watch(customerRepositoryProvider).watchCustomerTags(id),
);
final customerContactsProvider =
    StreamProvider.family<List<CustomerContact>, String>(
      (ref, id) => ref.watch(customerRepositoryProvider).watchContacts(id),
    );
final customerCustomFieldDefinitionsProvider =
    StreamProvider<List<CustomerCustomFieldDefinition>>(
      (ref) =>
          ref.watch(customerRepositoryProvider).watchCustomFieldDefinitions(),
    );
final customerCustomFieldValuesProvider =
    StreamProvider.family<List<CustomerCustomFieldValue>, String>(
      (ref, id) =>
          ref.watch(customerRepositoryProvider).watchCustomFieldValues(id),
    );
final customerFollowUpsProvider =
    StreamProvider.family<List<CustomerFollowUp>, String>(
      (ref, id) => ref.watch(customerRepositoryProvider).watchFollowUps(id),
    );
final latestCustomerFollowUpProvider =
    StreamProvider.family<CustomerFollowUp?, String>(
      (ref, id) =>
          ref.watch(customerRepositoryProvider).watchLatestFollowUp(id),
    );
final latestCustomerNextActionProvider =
    StreamProvider.family<CustomerFollowUp?, String>(
      (ref, id) =>
          ref.watch(customerRepositoryProvider).watchLatestNextAction(id),
    );
final customerFollowUpSearchProvider =
    StreamProvider.family<
      List<CustomerFollowUp>,
      ({String customerId, String search, int limit})
    >(
      (ref, query) => ref
          .watch(customerRepositoryProvider)
          .watchFollowUps(
            query.customerId,
            search: query.search,
            limit: query.limit,
          ),
    );
final latestCustomerNoteProvider = StreamProvider.family<CustomerNote?, String>(
  (ref, id) => ref.watch(customerRepositoryProvider).watchLatestNote(id),
);
final customerNotesProvider =
    StreamProvider.family<
      List<CustomerNote>,
      ({String customerId, String search, int limit})
    >(
      (ref, query) => ref
          .watch(customerRepositoryProvider)
          .watchNotes(
            query.customerId,
            search: query.search,
            limit: query.limit,
          ),
    );
