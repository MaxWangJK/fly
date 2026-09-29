import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

enum WorkspaceFolderKind { files, notes }

class WorkspaceFolder {
  const WorkspaceFolder({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.parentId,
    this.deletedAt,
  });
  final String id, name;
  final String? parentId;
  final int sortOrder;
  final DateTime? deletedAt;
}

/// One implementation of tree invariants; files and notes remain separate tables.
class WorkspaceFolderRepository {
  WorkspaceFolderRepository(this.db, this.kind);
  final AppDatabase db;
  final WorkspaceFolderKind kind;
  String get _table =>
      kind == WorkspaceFolderKind.files ? 'file_folders' : 'note_folders';
  Set<TableInfo> get _reads =>
      kind == WorkspaceFolderKind.files ? {db.fileFolders} : {db.noteFolders};
  String get _items =>
      kind == WorkspaceFolderKind.files ? 'attachments' : 'workspace_notes';
  Set<TableInfo> get _writes => {
    ..._reads,
    if (kind == WorkspaceFolderKind.files)
      db.attachments
    else
      db.workspaceNotes,
  };

  Stream<List<WorkspaceFolder>> watch({bool deleted = false}) => db
      .customSelect(
        'SELECT * FROM $_table WHERE deleted_at IS ${deleted ? 'NOT ' : ''}NULL ORDER BY sort_order, name',
        readsFrom: _reads,
      )
      .watch()
      .map((rows) => rows.map(_map).toList());

  Future<List<WorkspaceFolder>> all() async =>
      (await db.customSelect('SELECT * FROM $_table', readsFrom: _reads).get())
          .map(_map)
          .toList();
  WorkspaceFolder _map(QueryRow row) => WorkspaceFolder(
    id: row.read('id'),
    name: row.read('name'),
    parentId: row.readNullable('parent_id'),
    sortOrder: row.read('sort_order'),
    deletedAt: row.readNullable<DateTime>('deleted_at'),
  );
  static String checkedName(String input) {
    final name = input.trim();
    if (name.isEmpty ||
        name.length > 200 ||
        name == '.' ||
        name == '..' ||
        RegExp(r'[\x00-\x1f<>:"/\\|?*]').hasMatch(name)) {
      throw ArgumentError('名称不能为空，且不能包含路径或特殊字符');
    }
    return name;
  }

  Future<void> _validateParent(
    String? parent,
    List<WorkspaceFolder> folders,
  ) async {
    if (parent != null &&
        !folders.any((f) => f.id == parent && f.deletedAt == null)) {
      throw StateError('目标文件夹不存在或已删除');
    }
  }

  Set<String> descendants(String root, Iterable<WorkspaceFolder> folders) {
    final result = <String>{root};
    var changed = true;
    while (changed) {
      changed = false;
      for (final f in folders) {
        if (result.contains(f.parentId) && result.add(f.id)) changed = true;
      }
    }
    return result;
  }

  Future<String> create(
    String name, {
    String? parentId,
  }) => db.transaction(() async {
    final title = checkedName(name);
    final folders = await all();
    await _validateParent(parentId, folders);
    if (folders.any(
      (f) =>
          f.deletedAt == null &&
          f.parentId == parentId &&
          f.name.toLowerCase() == title.toLowerCase(),
    )) {
      throw StateError('同级文件夹名称已存在');
    }
    final id = const Uuid().v7();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customInsert(
      'INSERT INTO $_table (id,parent_id,name,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?)',
      variables: [
        Variable(id),
        Variable<String>(parentId),
        Variable(title),
        Variable(folders.length),
        Variable(now),
        Variable(now),
      ],
      updates: _reads,
    );
    return id;
  });
  Future<void> rename(String id, String name) => db.transaction(() async {
    final title = checkedName(name);
    final folders = await all();
    final current = folders
        .where((f) => f.id == id && f.deletedAt == null)
        .firstOrNull;
    if (current == null) throw StateError('文件夹不存在');
    if (folders.any(
      (f) =>
          f.id != id &&
          f.deletedAt == null &&
          f.parentId == current.parentId &&
          f.name.toLowerCase() == title.toLowerCase(),
    )) {
      throw StateError('同级文件夹名称已存在');
    }
    await db.customUpdate(
      'UPDATE $_table SET name=?,updated_at=? WHERE id=?',
      variables: [Variable(title), Variable(DateTime.now()), Variable(id)],
      updates: _reads,
    );
  });
  Future<void> move(String id, String? parentId) => db.transaction(() async {
    final folders = await all();
    final current = folders
        .where((f) => f.id == id && f.deletedAt == null)
        .firstOrNull;
    if (current == null) throw StateError('文件夹不存在');
    await _validateParent(parentId, folders);
    if (parentId != null && descendants(id, folders).contains(parentId)) {
      throw StateError('不能移动到自身或子文件夹');
    }
    if (folders.any(
      (f) =>
          f.id != id &&
          f.deletedAt == null &&
          f.parentId == parentId &&
          f.name.toLowerCase() == current.name.toLowerCase(),
    )) {
      throw StateError('目标位置已有同名文件夹');
    }
    await db.customUpdate(
      'UPDATE $_table SET parent_id=?,updated_at=? WHERE id=?',
      variables: [
        Variable<String>(parentId),
        Variable(DateTime.now()),
        Variable(id),
      ],
      updates: _reads,
    );
  });
  Future<void> remove(String id) => db.transaction(() async {
    final folders = await all();
    if (!folders.any((f) => f.id == id && f.deletedAt == null)) {
      throw StateError('文件夹不存在');
    }
    final ids = descendants(id, folders);
    final placeholders = List.filled(ids.length, '?').join(',');
    final now = DateTime.now();
    final batch = const Uuid().v7();
    final vars = [
      Variable(now),
      Variable(now),
      Variable(batch),
      ...ids.map(Variable.new),
    ];
    await db.customUpdate(
      'UPDATE $_table SET deleted_at=?,updated_at=?,deletion_batch=? WHERE deleted_at IS NULL AND id IN ($placeholders)',
      variables: vars,
      updates: _reads,
    );
    await db.customUpdate(
      'UPDATE $_items SET deleted_at=?,updated_at=?,deletion_batch=? WHERE deleted_at IS NULL AND folder_id IN ($placeholders)',
      variables: vars,
      updates: _writes,
    );
  });
  Future<void> restore(String id) => db.transaction(() async {
    final row = await db
        .customSelect(
          'SELECT * FROM $_table WHERE id=?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    final batch = row?.readNullable<String>('deletion_batch');
    if (row == null || batch == null) throw StateError('文件夹无法恢复');
    final parent = row.readNullable<String>('parent_id');
    final folders = await all();
    final destination =
        folders.any((f) => f.id == parent && f.deletedAt == null)
        ? parent
        : null;
    if (folders.any(
      (f) =>
          f.deletedAt == null &&
          f.parentId == destination &&
          f.name.toLowerCase() == row.read<String>('name').toLowerCase(),
    )) {
      throw StateError('恢复位置存在同名文件夹，请先重命名现有文件夹');
    }
    await db.customUpdate(
      'UPDATE $_table SET parent_id=? WHERE id=?',
      variables: [Variable<String>(destination), Variable(id)],
      updates: _reads,
    );
    final ids = descendants(id, folders);
    final placeholders = List.filled(ids.length, '?').join(',');
    for (final table in [_table, _items]) {
      final key = table == _table ? 'id' : 'folder_id';
      await db.customUpdate(
        'UPDATE $table SET deleted_at=NULL,deletion_batch=NULL,updated_at=? WHERE deletion_batch=? AND $key IN ($placeholders)',
        variables: [
          Variable(DateTime.now()),
          Variable(batch),
          ...ids.map(Variable.new),
        ],
        updates: _writes,
      );
    }
  });
}
