import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'file_browser_query.dart';

/// Device preferences are excluded from the sync settings allowlist.
class FileBrowserPreferences {
  const FileBrowserPreferences({
    required this.view,
    this.sort = FileSort.modified,
    this.imagesFirst = true,
    this.collection = FileCollection.recent,
    this.folderId,
    this.includeChildren = false,
    this.fileTags = const {},
    this.customerTags = const {},
  });
  final String view;
  final FileSort sort;
  final FileCollection collection;
  final String? folderId;
  final bool imagesFirst, includeChildren;
  final Set<String> fileTags, customerTags;
  Map<String, Object?> toJson() => {
    'view': view,
    'collection': collection.name,
    'folderId': folderId,
    'sort': sort.name,
    'imagesFirst': imagesFirst,
    'includeChildren': includeChildren,
    'fileTags': fileTags.toList(),
    'customerTags': customerTags.toList(),
  };
}

class FileBrowserPreferencesStore {
  FileBrowserPreferencesStore(this.db, {required this.phone});
  final AppDatabase db;
  final bool phone;
  Future<void> _writes = Future.value();
  String get key => 'fileBrowserPreferences.${phone ? 'phone' : 'desktop'}';
  Future<FileBrowserPreferences> load() async {
    final row = await (db.select(
      db.appSettings,
    )..where((r) => r.key.equals(key))).getSingleOrNull();
    Map<String, dynamic> data = {};
    if (row != null) {
      try {
        data = (jsonDecode(row.value) as Map).cast<String, dynamic>();
      } on FormatException {
        /* Corrupt preference values use defaults. */
      } on TypeError {
        /* Ignore older or invalid preference formats. */
      }
    }
    final own = (await db.select(db.fileTags).get()).map((t) => t.id).toSet();
    final crm =
        (await (db.select(db.tags)..where(
                  (t) =>
                      t.scope.equals('customer') &
                      t.deletedAt.isNull() &
                      t.isActive.equals(true),
                ))
                .get())
            .map((t) => t.id)
            .toSet();
    Set<String> tags(String key, Set<String> valid) => data[key] is List
        ? (data[key] as List).whereType<String>().where(valid.contains).toSet()
        : {};
    final view = data['view'];
    final collection =
        FileCollection.values
            .where((c) => c.name == data['collection'])
            .firstOrNull ??
        FileCollection.recent;
    String? folderId = data['folderId'] is String
        ? data['folderId'] as String
        : null;
    if (folderId != null &&
        await (db.select(db.fileFolders)
                  ..where((f) => f.id.equals(folderId!) & f.deletedAt.isNull()))
                .getSingleOrNull() ==
            null) {
      folderId = null;
    }
    return FileBrowserPreferences(
      collection: collection,
      folderId: folderId,
      view:
          (phone ? ['small', 'list'] : ['small', 'medium', 'list']).contains(
            view,
          )
          ? view as String
          : phone
          ? 'small'
          : 'list',
      sort:
          FileSort.values.where((s) => s.name == data['sort']).firstOrNull ??
          FileSort.modified,
      imagesFirst: data['imagesFirst'] != false,
      includeChildren: data['includeChildren'] == true,
      fileTags: tags('fileTags', own),
      customerTags: tags('customerTags', crm),
    );
  }

  Future<void> save(FileBrowserPreferences value) {
    final json = jsonEncode(value.toJson());
    final next = _writes.then(
      (_) => db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: key,
              value: json,
              updatedAt: DateTime.now(),
            ),
          ),
    );
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next.then<void>((_) {});
  }
}
