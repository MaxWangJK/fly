import 'dart:convert';

import '../../core/database/app_database.dart';
import '../../features/customers/domain/customer.dart';
import '../../features/files/data/file_browser_query.dart';
import '../../features/knowledge/data/knowledge_repository.dart';
import 'fuzzy_match.dart';

import 'package:drift/drift.dart';

enum SearchResultType {
  customer,
  order,
  task,
  note,
  followUp,
  file,
  workspaceNote,
  knowledge,
  tag,
}

class FlySearchResult {
  const FlySearchResult({
    required this.type,
    required this.entityId,
    required this.title,
    required this.subtitle,
    required this.matchedText,
    required this.score,
    this.tagCounts = const {},
  });

  final SearchResultType type;
  final String entityId;
  final String title;
  final String subtitle;
  final String matchedText;
  final int score;
  final Map<SearchResultType, int> tagCounts;
}

class GlobalSearchService {
  GlobalSearchService(
    this._db, {
    this.knowledge,
    this.includeWorkspaceNotes = true,
  });

  final AppDatabase _db;
  final KnowledgeRepository? knowledge;
  final bool includeWorkspaceNotes;

  static String _tagName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  // Definitions stay separate. Group display names without copying associations
  // or matching entity titles; duplicate links count an entity only once.
  Future<Map<String, List<FlySearchResult>>> _taggedEntities() async {
    final rows = await _db.customSelect('''
      SELECT t.name AS tag_name, 'customer' AS kind, c.id, c.name AS title,
        c.company_name AS subtitle FROM customer_tag_links l
        JOIN tags t ON t.id=l.tag_id JOIN customers c ON c.id=l.customer_id
        WHERE t.deleted_at IS NULL AND t.is_active=1 AND c.deleted_at IS NULL
      UNION ALL
      SELECT t.name, 'order', o.id, o.order_number, '' FROM order_tag_links l
        JOIN tags t ON t.id=l.tag_id JOIN orders o ON o.id=l.order_id
        WHERE t.deleted_at IS NULL AND t.is_active=1 AND o.deleted_at IS NULL
      UNION ALL
      SELECT t.name, 'workspaceNote', n.id, n.title, '' FROM note_tag_links l
        JOIN tags t ON t.id=l.tag_id JOIN workspace_notes n ON n.id=l.note_id
        WHERE t.deleted_at IS NULL AND t.is_active=1 AND n.deleted_at IS NULL
      UNION ALL
      SELECT t.name, 'file', a.id,
        coalesce(nullif(a.display_name,''),a.original_name), '' FROM file_tag_links l
        JOIN file_tags t ON t.id=l.tag_id JOIN attachments a ON a.id=l.file_id
        WHERE a.deleted_at IS NULL
    ''').get();
    final groups = <String, Map<String, FlySearchResult>>{};
    for (final row in rows) {
      final name = row.read<String>('tag_name');
      final kind = SearchResultType.values.byName(row.read<String>('kind'));
      if (kind == SearchResultType.workspaceNote && !includeWorkspaceNotes) {
        continue;
      }
      final id = row.read<String>('id');
      groups.putIfAbsent(
        '${kind.name}:${_tagName(name)}',
        () => {},
      )['${kind.name}:$id'] = FlySearchResult(
        type: kind,
        entityId: id,
        title: row.read<String>('title'),
        subtitle: row.read<String>('subtitle'),
        matchedText: name,
        score: 0,
      );
    }
    return {
      for (final group in groups.entries)
        group.key: group.value.values.toList(),
    };
  }

  Future<List<FlySearchResult>> searchTag(String name) async {
    final groups = await _taggedEntities();
    final results =
        groups[name] ??
        [
          for (final entry in groups.entries)
            if (entry.key.substring(entry.key.indexOf(':') + 1) ==
                _tagName(name))
              ...entry.value,
        ];
    results.sort((a, b) {
      final group = a.type.index.compareTo(b.type.index);
      return group != 0
          ? group
          : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return results;
  }

  Future<List<FlySearchResult>> search(
    String input, {
    int perGroup = 6,
    String Function(String)? translate,
  }) async {
    String copy(String value) => translate?.call(value) ?? value;
    final term = input.trim();
    if (term.isEmpty) return const [];

    final customers = await (_db.select(
      _db.customers,
    )..where((row) => row.deletedAt.isNull())).get();
    final customerNames = {for (final row in customers) row.id: row.name};
    final results = <FlySearchResult>[];

    for (final row in customers) {
      final fields = [
        row.name,
        row.companyName,
        row.whatsapp,
        row.email,
        row.facebook,
      ];
      final match = _bestMatch(term, fields);
      if (match != null) {
        results.add(
          FlySearchResult(
            type: SearchResultType.customer,
            entityId: row.id,
            title: row.name,
            subtitle: row.companyName.isEmpty ? copy('客户') : row.companyName,
            matchedText: match.value,
            score: 400 + match.score,
          ),
        );
      }
      final nextActionType =
          NextActionTypeX.parse(row.nextActionType)?.label ?? '';
      final next = _bestMatch(term, [
        row.notes,
        row.nextAction,
        nextActionType,
      ]);
      if (next != null) {
        results.add(
          FlySearchResult(
            type: SearchResultType.note,
            entityId: row.id,
            title: row.name,
            subtitle: FuzzyMatch.matches(term, [row.nextAction, nextActionType])
                ? copy('下一步')
                : copy('客户备注'),
            matchedText: next.value,
            score: 100 + next.score,
          ),
        );
      }
    }

    final orders = await (_db.select(
      _db.orders,
    )..where((row) => row.deletedAt.isNull())).get();
    final items = await (_db.select(
      _db.orderProductionItems,
    )..where((row) => row.deletedAt.isNull())).get();
    final factories = {
      for (final row in await _db.select(_db.factories).get()) row.id: row.name,
    };
    final products = {
      for (final row in await _db.select(_db.products).get()) row.id: row.name,
    };
    final itemTerms = <String, List<String>>{};
    for (final item in items) {
      itemTerms.putIfAbsent(item.orderId, () => []).addAll([
        factories[item.factoryId] ?? '',
        products[item.productId] ?? '',
      ]);
    }
    for (final row in orders) {
      final customer = customerNames[row.customerId] ?? '';
      final match = _bestMatch(term, [
        row.orderNumber,
        customer,
        ...?itemTerms[row.id],
      ]);
      if (match == null) continue;
      results.add(
        FlySearchResult(
          type: SearchResultType.order,
          entityId: row.id,
          title: row.orderNumber,
          subtitle: customer.isEmpty ? copy('订单') : customer,
          matchedText: match.value,
          score: 300 + match.score,
        ),
      );
    }

    final tasks = await (_db.select(
      _db.tasks,
    )..where((row) => row.deletedAt.isNull())).get();
    for (final row in tasks) {
      final match = _bestMatch(term, [row.title, row.description]);
      if (match == null) continue;
      results.add(
        FlySearchResult(
          type: SearchResultType.task,
          entityId: row.id,
          title: row.title,
          subtitle: row.description,
          matchedText: match.value,
          score: 200 + match.score,
        ),
      );
    }

    final notes = await (_db.select(
      _db.customerNotes,
    )..where((row) => row.deletedAt.isNull())).get();
    for (final row in notes) {
      if (!customerNames.containsKey(row.customerId)) continue;
      final match = _bestMatch(term, [row.content]);
      if (match == null) continue;
      results.add(
        FlySearchResult(
          type: SearchResultType.note,
          entityId: row.customerId,
          title: customerNames[row.customerId] ?? copy('客户备注'),
          subtitle: copy('客户备注'),
          matchedText: match.value,
          score: 100 + match.score,
        ),
      );
    }

    final followUps = await (_db.select(
      _db.customerFollowUps,
    )..where((row) => row.deletedAt.isNull())).get();
    for (final row in followUps) {
      if (!customerNames.containsKey(row.customerId)) continue;
      final match = _bestMatch(term, [row.content, row.nextAction]);
      if (match == null) continue;
      results.add(
        FlySearchResult(
          type: SearchResultType.followUp,
          entityId: row.customerId,
          title: customerNames[row.customerId] ?? copy('跟进记录'),
          subtitle: '${copy('跟进记录')} · ${row.channel}',
          matchedText: match.value,
          score: 100 + match.score,
        ),
      );
    }

    final files = await FileBrowserQuery(_db)
        .watch(collection: FileCollection.recent, search: term)
        .first;
    for (final entry in files) {
      results.add(
        FlySearchResult(
          type: SearchResultType.file,
          entityId: entry.file.id,
          title: entry.name,
          subtitle: [
            entry.customerName,
            entry.orderNumber,
          ].where((value) => value.isNotEmpty).join(' · '),
          matchedText: entry.fileTags,
          score: 250,
        ),
      );
    }
    final folderFiles = await _db
        .customSelect(
          "SELECT a.id, a.display_name, a.original_name, f.name AS folder_name FROM attachments a JOIN file_folders f ON f.id=a.folder_id WHERE a.deleted_at IS NULL AND f.deleted_at IS NULL",
        )
        .get();
    for (final row
        in folderFiles
            .where(
              (row) =>
                  FuzzyMatch.matches(term, [row.read<String>('folder_name')]),
            )
            .take(perGroup)) {
      final id = row.read<String>('id');
      if (results.any(
        (r) => r.type == SearchResultType.file && r.entityId == id,
      )) {
        continue;
      }
      final name = row.read<String>('display_name');
      results.add(
        FlySearchResult(
          type: SearchResultType.file,
          entityId: id,
          title: name.isEmpty ? row.read('original_name') : name,
          subtitle: row.read('folder_name'),
          matchedText: row.read('folder_name'),
          score: 230,
        ),
      );
    }
    if (includeWorkspaceNotes) {
      final workspaceNotes = await (_db.select(
        _db.workspaceNotes,
      )..where((r) => r.deletedAt.isNull())).get();
      final noteIds = workspaceNotes.map((n) => n.id).toSet();
      final blockTerms = <String, List<String>>{};
      final noteTags = await _db.select(_db.noteTagLinks).join([
        innerJoin(
          _db.tags,
          _db.tags.id.equalsExp(_db.noteTagLinks.tagId) &
              _db.tags.deletedAt.isNull(),
        ),
      ]).get();
      for (final row in noteTags) {
        final link = row.readTable(_db.noteTagLinks);
        if (noteIds.contains(link.noteId)) {
          blockTerms
              .putIfAbsent(link.noteId, () => [])
              .add(row.readTable(_db.tags).name);
        }
      }
      for (final block in await _db.select(_db.noteBlocks).get()) {
        if (!noteIds.contains(block.noteId)) continue;
        try {
          final content = jsonDecode(block.contentJson);
          if (content is! Map) continue;
          final values = blockTerms.putIfAbsent(block.noteId, () => []);
          for (final key in ['text', 'caption']) {
            if (content[key] is String) values.add(content[key] as String);
          }
          final rows = content['rows'];
          if (rows is List) {
            for (final row in rows.whereType<List>()) {
              values.addAll(row.whereType<String>());
            }
          }
        } on FormatException {
          // An unreadable legacy block must not prevent searching other notes.
        }
      }
      for (final note in workspaceNotes) {
        final match = _bestMatch(term, [note.title, ...?blockTerms[note.id]]);
        if (match != null) {
          results.add(
            FlySearchResult(
              type: SearchResultType.workspaceNote,
              entityId: note.id,
              title: note.title,
              subtitle: copy('笔记'),
              matchedText: match.value,
              score: 240 + match.score,
            ),
          );
        }
      }
    }
    if (knowledge != null) {
      try {
        for (final article in await knowledge!.search(term, limit: perGroup)) {
          final match = _bestMatch(term, [
            article.title,
            article.summary,
            ...article.tags,
            ...article.keywords,
            article.plainText,
          ]);
          results.add(
            FlySearchResult(
              type: SearchResultType.knowledge,
              entityId: article.id,
              title: article.title,
              subtitle: article.summary,
              matchedText: match?.value ?? article.title,
              score: 260 + (match?.score ?? 0),
            ),
          );
        }
      } catch (_) {
        // An unavailable official pack must not hide CRM or personal results.
      }
    }
    for (final group in (await _taggedEntities()).entries) {
      if (!FuzzyMatch.matches(term, [
        group.key.substring(group.key.indexOf(':') + 1),
      ])) {
        continue;
      }
      final counts = <SearchResultType, int>{};
      for (final entity in group.value) {
        counts.update(entity.type, (n) => n + 1, ifAbsent: () => 1);
        if (!results.any(
          (r) => r.type == entity.type && r.entityId == entity.entityId,
        )) {
          results.add(
            FlySearchResult(
              type: entity.type,
              entityId: entity.entityId,
              title: entity.title,
              subtitle: entity.subtitle,
              matchedText: entity.matchedText,
              score: 220,
            ),
          );
        }
      }
      results.add(
        FlySearchResult(
          type: SearchResultType.tag,
          entityId: group.key,
          title: group.value.first.matchedText,
          subtitle: '',
          matchedText: '',
          score: 500,
          tagCounts: Map.unmodifiable(counts),
        ),
      );
    }
    results.sort((left, right) => right.score.compareTo(left.score));
    final counts = <SearchResultType, int>{};
    return results.where((result) {
      final count = counts[result.type] ?? 0;
      if (count >= perGroup) return false;
      counts[result.type] = count + 1;
      return true;
    }).toList();
  }

  _Match? _bestMatch(String term, Iterable<String> fields) {
    final values = fields.toList();
    final combined = FuzzyMatch.score(term, values);
    if (combined == null) return null;
    _Match? best;
    for (final raw in values) {
      final value = raw.trim();
      final score = FuzzyMatch.score(term, [value]);
      if (score == null) continue;
      if (best == null || score > best.score) best = _Match(value, score);
    }
    return best ?? _Match(values.firstWhere((v) => v.isNotEmpty), combined);
  }
}

class _Match {
  const _Match(this.value, this.score);
  final String value;
  final int score;
}
