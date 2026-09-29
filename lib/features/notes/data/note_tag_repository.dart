import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/data/tag_garbage_collector.dart';

/// Notes share tag definitions, never customer/order application links.
class NoteTagRepository {
  const NoteTagRepository(this.db);
  final AppDatabase db;

  Future<List<TagRecord>> suggestions(String noteId, String input) async {
    final term = input
        .trim()
        .replaceFirst(RegExp(r'^#+\s*'), '')
        .trim()
        .toLowerCase();
    if (term.isEmpty) return const [];
    final rows = await db
        .customSelect(
          '''SELECT t.* FROM tags t
      WHERE t.scope='note' AND t.deleted_at IS NULL AND t.is_active=1 AND instr(lower(t.name),?)>0
      AND NOT EXISTS(SELECT 1 FROM note_tag_links l WHERE l.note_id=? AND l.tag_id=t.id)
      ORDER BY CASE WHEN lower(t.name)=? THEN 0 ELSE 1 END, t.name COLLATE NOCASE, t.id
      LIMIT 5''',
          variables: [Variable(term), Variable(noteId), Variable(term)],
        )
        .get();
    return rows.map((row) => db.tags.map(row.data)).toList();
  }

  Stream<List<TagRecord>> watch(String noteId) =>
      (db.select(db.tags)..where((t) => t.deletedAt.isNull()))
          .join([
            innerJoin(
              db.noteTagLinks,
              db.noteTagLinks.tagId.equalsExp(db.tags.id) &
                  db.noteTagLinks.noteId.equals(noteId),
            ),
          ])
          .watch()
          .map((rows) => rows.map((r) => r.readTable(db.tags)).toList());

  Future<void> _requireNote(String id) async {
    final note = await (db.select(
      db.workspaceNotes,
    )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).getSingleOrNull();
    if (note == null) throw StateError('Note is missing or deleted.');
  }

  Future<String> add(String noteId, String input) => db.transaction(() async {
    await _requireNote(noteId);
    final name = input
        .trim()
        .replaceFirst(RegExp(r'^#+\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.isEmpty || name.length > 80) {
      throw ArgumentError('Tag name must contain 1–80 characters.');
    }
    final existing = await (db.select(
      db.tags,
    )..where((t) => t.scope.equals('note'))).get();
    final matches =
        existing
            .where(
              (t) =>
                  t.name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase() ==
                  name.toLowerCase(),
            )
            .toList()
          ..sort(
            (a, b) => (a.deletedAt == null ? 0 : 1).compareTo(
              b.deletedAt == null ? 0 : 1,
            ),
          );
    final now = DateTime.now();
    final id = matches.isEmpty ? const Uuid().v7() : matches.first.id;
    if (matches.isEmpty) {
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(
              id: id,
              scope: const Value('note'),
              name: name,
              createdAt: now,
              updatedAt: now,
            ),
          );
    } else if (matches.first.deletedAt != null || !matches.first.isActive) {
      await (db.update(db.tags)..where((r) => r.id.equals(id))).write(
        TagsCompanion(
          deletedAt: const Value(null),
          isActive: const Value(true),
          updatedAt: Value(now),
          version: Value(matches.first.version + 1),
        ),
      );
    }
    await db
        .into(db.noteTagLinks)
        .insert(
          NoteTagLinksCompanion.insert(noteId: noteId, tagId: id),
          mode: InsertMode.insertOrIgnore,
        );
    return id;
  });

  Future<void> remove(String noteId, String tagId) => db.transaction(() async {
    await _requireNote(noteId);
    await (db.delete(
      db.noteTagLinks,
    )..where((r) => r.noteId.equals(noteId) & r.tagId.equals(tagId))).go();
    await TagCleanupService(db).collectCandidates([tagId]);
  });
}
