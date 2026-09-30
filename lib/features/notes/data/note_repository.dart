import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/search/fuzzy_match.dart';
import '../domain/note_block.dart';

class NoteConflict implements Exception {
  @override
  String toString() => '笔记已在其它位置更新；请保留当前内容并重新加载后合并';
}

class NoteRepository {
  NoteRepository(this.db);
  final AppDatabase db;
  Future<void> writeDraft(String id, NoteDraft draft) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'noteDraft:$id',
          value: draft.encode(),
          updatedAt: DateTime.now(),
        ),
      );
  Future<NoteDraft?> readDraft(String id) async {
    final row = await (db.select(
      db.appSettings,
    )..where((r) => r.key.equals('noteDraft:$id'))).getSingleOrNull();
    return row == null ? null : NoteDraft.decode(row.value);
  }

  Future<void> clearDraft(String id, NoteDraft draft) =>
      (db.delete(db.appSettings)..where(
            (r) =>
                r.key.equals('noteDraft:$id') & r.value.equals(draft.encode()),
          ))
          .go();
  Future<void> clearSavedDraft(
    String id,
    String title,
    List<NoteBlock> blocks,
  ) async {
    final draft = await readDraft(id);
    if (draft != null && draft.matches(title, blocks)) {
      await clearDraft(id, draft);
    }
  }

  Future<String> recoverCopy(String sourceId, NoteDraft draft) =>
      db.transaction(() async {
        final name = draft.title.trim();
        final title = name.isEmpty
            ? '恢复的笔记'
            : '${name.length > 480 ? name.substring(0, 480) : name}（草稿副本）';
        final id = await create(title);
        await save(
          id,
          title: title,
          expectedRevision: 1,
          blocks: [
            for (final b in draft.blocks)
              NoteBlock.encoded(
                id: const Uuid().v7(),
                type: b.type,
                contentJson: b.contentJson,
              ),
          ],
        );
        await clearDraft(sourceId, draft);
        return id;
      });
  Stream<List<WorkspaceNoteRecord>> watch({
    String? folderId,
    bool recent = false,
    bool favorites = false,
    bool deleted = false,
    String search = '',
  }) {
    final term = search.trim();
    if (term.isNotEmpty) {
      final where = <String>[
        deleted ? 'n.deleted_at IS NOT NULL' : 'n.deleted_at IS NULL',
      ];
      final variables = <Variable>[];
      if (favorites) {
        where.add('n.is_favorite=1');
      } else if (!recent && !deleted) {
        if (folderId == null) {
          where.add('n.folder_id IS NULL');
        } else {
          where.add('n.folder_id=?');
          variables.add(Variable(folderId));
        }
      }
      final manualOrder = !recent && !favorites && !deleted
          ? 'n.manual_sort_order IS NULL, n.manual_sort_order, '
          : '';
      return db
          .customSelect(
            '''
        SELECT n.*,
          coalesce((SELECT group_concat(t.name,' ') FROM note_tag_links l
            JOIN tags t ON t.id=l.tag_id WHERE l.note_id=n.id
            AND t.deleted_at IS NULL AND t.is_active=1),'') AS tag_names,
          coalesce((SELECT group_concat(b.content_json,' ') FROM note_blocks b
            WHERE b.note_id=n.id),'') AS block_text
        FROM workspace_notes n WHERE ${where.join(' AND ')}
        ORDER BY $manualOrder n.created_at DESC, n.id
      ''',
            variables: variables,
            readsFrom: {
              db.workspaceNotes,
              db.noteTagLinks,
              db.tags,
              db.noteBlocks,
            },
          )
          .watch()
          .map((rows) {
            final matches = rows.where(
              (row) => FuzzyMatch.matches(term, [
                row.read<String>('title'),
                row.read<String>('tag_names'),
                row.read<String>('block_text'),
              ]),
            );
            final limited = recent ? matches.take(100) : matches;
            return limited
                .map((row) => db.workspaceNotes.map(row.data))
                .toList();
          });
    }
    final query = db.select(db.workspaceNotes)
      ..where((r) => deleted ? r.deletedAt.isNotNull() : r.deletedAt.isNull());
    if (favorites) {
      query.where((r) => r.isFavorite.equals(true));
    } else if (!recent && !deleted) {
      query.where(
        (r) => folderId == null
            ? r.folderId.isNull()
            : r.folderId.equals(folderId),
      );
    }
    query.orderBy([
      if (!recent && !favorites && !deleted) ...[
        (r) => OrderingTerm.asc(r.manualSortOrder.isNull()),
        (r) => OrderingTerm.asc(r.manualSortOrder),
      ],
      (r) => OrderingTerm.desc(r.createdAt),
      (r) => OrderingTerm.asc(r.id),
    ]);
    if (recent) query.limit(100);
    return query.watch();
  }

  Future<WorkspaceNoteRecord?> get(String id) => (db.select(
    db.workspaceNotes,
  )..where((r) => r.id.equals(id))).getSingleOrNull();

  Stream<WorkspaceNoteRecord?> watchNote(String id) => (db.select(
    db.workspaceNotes,
  )..where((r) => r.id.equals(id))).watchSingleOrNull();

  Future<void> moveInFolder(String id, int direction) =>
      db.transaction(() async {
        final note = await get(id);
        if (note == null || note.deletedAt != null) return;
        final items = await watch(folderId: note.folderId).first;
        final from = items.indexWhere((item) => item.id == id);
        final to = from + direction;
        if (from < 0 || to < 0 || to >= items.length) return;
        items.insert(to, items.removeAt(from));
        for (var i = 0; i < items.length; i++) {
          await (db.update(db.workspaceNotes)
                ..where((r) => r.id.equals(items[i].id)))
              .write(WorkspaceNotesCompanion(manualSortOrder: Value(i)));
        }
      });

  /// Only visible list rows subscribe; bound both block count and displayed text.
  Stream<String> watchPreview(String id) =>
      (db.select(db.noteBlocks)
            ..where((r) => r.noteId.equals(id))
            ..orderBy([(r) => OrderingTerm.asc(r.sortOrder)])
            ..limit(3))
          .watch()
          .map(
            (rows) => rows
                .map((row) {
                  try {
                    final content = jsonDecode(row.contentJson);
                    if (content is! Map) return '';
                    final text = content['text'] ?? content['caption'];
                    if (text is String && text.trim().isNotEmpty) {
                      return text.replaceAll(RegExp(r'\s+'), ' ').trim();
                    }
                    return switch (row.type) {
                      'image' => '[图片]',
                      'attachment' => '[附件]',
                      'table' => '[表格]',
                      _ => '',
                    };
                  } on FormatException {
                    return '';
                  }
                })
                .where((text) => text.isNotEmpty)
                .join(' · '),
          )
          .map((text) => text.runes.take(160).map(String.fromCharCode).join());
  Future<List<NoteBlock>> blocks(String id) async =>
      (await (db.select(db.noteBlocks)
                ..where((r) => r.noteId.equals(id))
                ..orderBy([(r) => OrderingTerm.asc(r.sortOrder)]))
              .get())
          .map(
            (r) => NoteBlock.encoded(
              id: r.id,
              type: r.type,
              contentJson: r.contentJson,
            ),
          )
          .toList();
  Future<void> _folder(String? id) async {
    if (id != null &&
        await (db.select(db.noteFolders)
                  ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
                .getSingleOrNull() ==
            null) {
      throw StateError('笔记文件夹不存在');
    }
  }

  Future<String> create(String title, {String? folderId}) =>
      db.transaction(() async {
        await _folder(folderId);
        final name = title.trim();
        if (name.isEmpty || name.length > 500) {
          throw ArgumentError('请输入 1–500 字笔记标题');
        }
        final id = const Uuid().v7();
        final now = DateTime.now();
        await db
            .into(db.workspaceNotes)
            .insert(
              WorkspaceNotesCompanion.insert(
                id: id,
                folderId: Value(folderId),
                title: name,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.noteBlocks)
            .insert(
              NoteBlocksCompanion.insert(
                id: const Uuid().v7(),
                noteId: id,
                type: 'paragraph',
                sortOrder: 0,
                contentJson: '{"text":""}',
                createdAt: now,
                updatedAt: now,
              ),
            );
        return id;
      });
  Future<int> save(
    String id, {
    required String title,
    required List<NoteBlock> blocks,
    required int expectedRevision,
  }) => db.transaction(() async {
    final name = title.trim();
    if (name.isEmpty || name.length > 500) {
      throw ArgumentError('笔记标题不能为空或超过 500 字');
    }
    if (blocks.map((b) => b.id).toSet().length != blocks.length) {
      throw ArgumentError('重复块 ID');
    }
    for (final b in blocks) {
      b.validate();
    }
    final current = await get(id);
    if (current == null || current.deletedAt != null) {
      throw StateError('笔记不存在或已删除');
    }
    if (current.revision != expectedRevision) throw NoteConflict();
    final now = DateTime.now();
    final updated =
        await (db.update(db.workspaceNotes)..where(
              (r) => r.id.equals(id) & r.revision.equals(expectedRevision),
            ))
            .write(
              WorkspaceNotesCompanion(
                title: Value(name),
                updatedAt: Value(now),
                revision: Value(expectedRevision + 1),
              ),
            );
    if (updated != 1) throw NoteConflict();
    final old = await (db.select(
      db.noteBlocks,
    )..where((r) => r.noteId.equals(id))).get();
    final dates = {for (final r in old) r.id: r.createdAt};
    await (db.delete(db.noteBlocks)..where((r) => r.noteId.equals(id))).go();
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      await db
          .into(db.noteBlocks)
          .insert(
            NoteBlocksCompanion.insert(
              id: b.id,
              noteId: id,
              type: b.type,
              sortOrder: i,
              contentJson: b.contentJson,
              createdAt: dates[b.id] ?? now,
              updatedAt: now,
            ),
          );
    }
    return expectedRevision + 1;
  });
  Future<void> favorite(String id, bool value) =>
      (db.update(
        db.workspaceNotes,
      )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).write(
        WorkspaceNotesCompanion(
          isFavorite: Value(value),
          updatedAt: Value(DateTime.now()),
        ),
      );
  Future<void> move(String id, String? folderId) => db.transaction(() async {
    await _folder(folderId);
    await (db.update(
      db.workspaceNotes,
    )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).write(
      WorkspaceNotesCompanion(
        folderId: Value(folderId),
        manualSortOrder: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });
  Future<void> remove(String id) =>
      (db.update(
        db.workspaceNotes,
      )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).write(
        WorkspaceNotesCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
  Future<void> restore(String id) => db.transaction(() async {
    final row = await get(id);
    if (row == null) throw StateError('笔记不存在');
    final parent = row.folderId == null
        ? null
        : await (db.select(db.noteFolders)..where(
                (r) => r.id.equals(row.folderId!) & r.deletedAt.isNull(),
              ))
              .getSingleOrNull();
    await (db.update(db.workspaceNotes)..where((r) => r.id.equals(id))).write(
      WorkspaceNotesCompanion(
        folderId: Value(parent?.id),
        deletedAt: const Value(null),
        deletionBatch: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });
}

class NoteDraft {
  const NoteDraft({
    required this.title,
    required this.blocks,
    required this.revision,
  });
  final String title;
  final List<NoteBlock> blocks;
  final int revision;
  bool matches(String savedTitle, List<NoteBlock> savedBlocks) =>
      title == savedTitle &&
      blocks.length == savedBlocks.length &&
      List.generate(
        blocks.length,
        (i) =>
            blocks[i].id == savedBlocks[i].id &&
            blocks[i].type == savedBlocks[i].type &&
            blocks[i].contentJson == savedBlocks[i].contentJson,
      ).every((v) => v);
  String encode() => jsonEncode({
    'title': title,
    'revision': revision,
    'blocks': [
      for (final b in blocks)
        {'id': b.id, 'type': b.type, 'contentJson': b.contentJson},
    ],
  });
  factory NoteDraft.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return NoteDraft(
      title: json['title'] as String,
      revision: json['revision'] as int,
      blocks: [
        for (final b in json['blocks'] as List)
          NoteBlock.encoded(
            id: b['id'] as String,
            type: b['type'] as String,
            contentJson: b['contentJson'] as String,
          ),
      ],
    );
  }
}
