import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../domain/tag_lifecycle.dart';

/// Centralized lifecycle policy for the shared Tag engine.
///
/// CRM cleanup never deletes category-owned tags or tags currently shared with
/// Tasks or Notes. Soft-deleted note references remain protected for restoration.
/// Ordinary tags are removed only after all relevant references disappear.
class TagCleanupService {
  const TagCleanupService(this.database);

  final AppDatabase database;

  Future<TagReferenceSummary> referencesFor(String tagId) async {
    final category =
        await (database.select(
              database.customerCategories,
            )..where((row) => row.tagId.equals(tagId) & row.deletedAt.isNull()))
            .getSingleOrNull();

    final customerReferences =
        await (database.select(
          database.customerTagLinks,
        )..where((row) => row.tagId.equals(tagId))).join([
          innerJoin(
            database.customers,
            database.customers.id.equalsExp(
                  database.customerTagLinks.customerId,
                ) &
                database.customers.deletedAt.isNull(),
          ),
        ]).get();

    final orderReferences =
        await (database.select(
          database.orderTagLinks,
        )..where((row) => row.tagId.equals(tagId))).join([
          innerJoin(
            database.orders,
            database.orders.id.equalsExp(database.orderTagLinks.orderId) &
                database.orders.deletedAt.isNull(),
          ),
        ]).get();

    final taskReferences =
        await (database.select(
          database.taskTags,
        )..where((row) => row.tagId.equals(tagId))).join([
          innerJoin(
            database.tasks,
            database.tasks.id.equalsExp(database.taskTags.taskId) &
                database.tasks.deletedAt.isNull(),
          ),
        ]).get();

    // Retain links belonging to deleted notes: restoring a note must restore
    // its tags too. Explicit removal of a link can still collect an orphan.
    final noteReferences = await (database.select(
      database.noteTagLinks,
    )..where((row) => row.tagId.equals(tagId))).get();
    return TagReferenceSummary(
      customerReferences: customerReferences.length,
      orderReferences: orderReferences.length,
      taskReferences: taskReferences.length,
      categoryLinked: category != null,
      noteReferences: noteReferences.length,
    );
  }

  Future<bool> isDeletableTag(String tagId) async =>
      (await referencesFor(tagId)).isOrphan;

  Future<int> cleanupOrphanTags() async {
    final tags = await (database.select(
      database.tags,
    )..where((row) => row.deletedAt.isNull())).get();
    var removed = 0;
    for (final tag in tags) {
      if (await _deleteIfOrphan(tag.id)) removed++;
    }
    return removed;
  }

  Future<int> collectCandidates(Iterable<String> candidateIds) async {
    var removed = 0;
    for (final tagId in candidateIds.toSet()) {
      if (await _deleteIfOrphan(tagId)) removed++;
    }
    return removed;
  }

  Future<void> deleteTagDefinition(String tagId) async {
    await database.transaction(() async {
      final references = await referencesFor(tagId);
      if (references.isProtected || references.noteReferences > 0) {
        throw StateError('Protected tags cannot be deleted.');
      }
      await (database.delete(
        database.customerTagLinks,
      )..where((row) => row.tagId.equals(tagId))).go();
      await (database.delete(
        database.orderTagLinks,
      )..where((row) => row.tagId.equals(tagId))).go();
      await (database.delete(
        database.taskTags,
      )..where((row) => row.tagId.equals(tagId))).go();
      await (database.delete(
        database.tags,
      )..where((row) => row.id.equals(tagId))).go();
    });
  }

  Future<bool> _deleteIfOrphan(String tagId) async {
    if (!await isDeletableTag(tagId)) return false;
    final count = await (database.delete(
      database.tags,
    )..where((row) => row.id.equals(tagId))).go();
    return count > 0;
  }
}

Future<void> collectUnusedTags(
  AppDatabase database,
  Iterable<String> candidateIds,
) => TagCleanupService(database).collectCandidates(candidateIds);
