import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../../../shared/search/fuzzy_match.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_pack_codec.dart';

typedef KnowledgeSeedLoader = Future<KnowledgeCatalog> Function();

class KnowledgeImportResult {
  const KnowledgeImportResult({
    required this.version,
    required this.added,
    required this.updated,
    required this.archived,
  });
  final String version;
  final int added;
  final int updated;
  final int archived;
}

class KnowledgeRepository {
  KnowledgeRepository({
    required this.db,
    required this.rootPath,
    required this.seedLoader,
    required this.publicKey,
    KnowledgePackCodec? codec,
  }) : codec = codec ?? KnowledgePackCodec();

  final AppDatabase db;
  final String? rootPath;
  final KnowledgeSeedLoader seedLoader;
  final List<int> publicKey;
  final KnowledgePackCodec codec;
  Future<KnowledgeCatalog>? _catalog;

  String get officialPath => p.join(rootPath!, 'knowledge', 'official');
  String get activePath => p.join(officialPath, 'active');

  Future<KnowledgeCatalog> load() => _catalog ??= _load();

  void refresh() => _catalog = null;

  Future<KnowledgeCatalog> _load() async {
    if (rootPath != null && publicKey.length == 32) {
      final manifest = File(p.join(activePath, 'manifest.json'));
      if (await manifest.exists()) {
        try {
          final files = <String, Uint8List>{};
          await for (final entity in Directory(
            activePath,
          ).list(recursive: true, followLinks: false)) {
            if (entity is! File) continue;
            final relative = p
                .relative(entity.path, from: activePath)
                .replaceAll('\\', '/');
            files[relative] = await entity.readAsBytes();
          }
          final archive = await _packFromFiles(files);
          return (await codec.verify(archive, publicKey: publicKey)).catalog;
        } catch (_) {
          // Never show unverified content; the bundled seed remains readable.
        }
      }
    }
    return seedLoader();
  }

  Future<KnowledgeImportResult> importPack(List<int> bytes) async {
    if (rootPath == null || publicKey.length != 32) {
      throw const KnowledgePackException(
        'Official pack signing key is not configured',
      );
    }
    final previous = await load();
    final verified = await codec.verify(
      bytes,
      publicKey: publicKey,
      currentVersion: previous.packVersion,
    );
    final official = Directory(officialPath);
    await official.create(recursive: true);
    final staging = Directory(
      p.join(
        official.path,
        '.staging-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final active = Directory(activePath);
    final backup = Directory(
      p.join(
        official.path,
        'packs',
        'backup-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await staging.create(recursive: true);
    var movedActive = false;
    try {
      for (final entry in verified.files.entries) {
        final target = File(p.joinAll([staging.path, ...entry.key.split('/')]));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.value, flush: true);
      }
      if (await active.exists()) {
        await backup.parent.create(recursive: true);
        await active.rename(backup.path);
        movedActive = true;
      }
      await staging.rename(active.path);
      refresh();
    } catch (_) {
      if (movedActive && !await active.exists() && await backup.exists()) {
        await backup.rename(active.path);
      }
      rethrow;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
    final oldIds = previous.articles.map((a) => a.id).toSet();
    final newIds = verified.catalog.articles.map((a) => a.id).toSet();
    final oldArticles = {for (final a in previous.articles) a.id: a};
    return KnowledgeImportResult(
      version: verified.catalog.packVersion,
      added: newIds.difference(oldIds).length,
      updated: verified.catalog.articles
          .where(
            (a) =>
                oldIds.contains(a.id) &&
                (oldArticles[a.id]!.version != a.version ||
                    oldArticles[a.id]!.markdown != a.markdown),
          )
          .length,
      archived: oldIds.difference(newIds).length,
    );
  }

  Future<List<int>> _packFromFiles(Map<String, Uint8List> files) async {
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    return ZipEncoder().encode(archive)!;
  }

  Future<Set<String>> favorites() async => {
    for (final row in await db.select(db.knowledgeFavorites).get())
      row.articleId,
  };

  Future<void> setFavorite(String articleId, bool value) async {
    final catalog = await load();
    if (catalog.article(articleId) == null) {
      throw StateError('Article not found');
    }
    if (value) {
      await db
          .into(db.knowledgeFavorites)
          .insertOnConflictUpdate(
            KnowledgeFavoritesCompanion.insert(
              articleId: articleId,
              createdAt: DateTime.now(),
            ),
          );
    } else {
      await (db.delete(
        db.knowledgeFavorites,
      )..where((row) => row.articleId.equals(articleId))).go();
    }
  }

  Future<List<KnowledgeArticle>> search(String query, {int limit = 30}) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final catalog = await load();
    final ranked = <(int, KnowledgeArticle)>[];
    for (final article in catalog.articles) {
      final title = FuzzyMatch.score(term, [article.title]) ?? 0;
      final summary = FuzzyMatch.score(term, [article.summary]) ?? 0;
      final tags =
          FuzzyMatch.score(term, [...article.tags, ...article.keywords]) ?? 0;
      final body = FuzzyMatch.score(term, [article.plainText]) ?? 0;
      final score = [
        title * 4,
        summary * 2,
        tags * 3,
        body,
      ].reduce((a, b) => a > b ? a : b);
      if (score > 0) ranked.add((score, article));
    }
    ranked.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final item in ranked.take(limit)) item.$2];
  }
}

/// Bundled Markdown is part of the application binary and is the only trusted
/// unsigned content. External packs must pass [KnowledgePackCodec.verify].
Future<KnowledgeCatalog> loadBundledKnowledge({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  const prefix = 'assets/knowledge/seed/';
  final catalogJson = jsonDecode(
    await assets.loadString('${prefix}catalog.json'),
  ) as Map<String, dynamic>;
  final categories = (catalogJson['categories'] as List)
      .map(
        (item) =>
            KnowledgeCategory.fromJson(Map<String, dynamic>.from(item as Map)),
      )
      .toList();
  final articles = <String, String>{};
  for (final path in (catalogJson['articles'] as List).cast<String>()) {
    articles['articles/$path'] = await assets.loadString('$prefix$path');
  }
  return KnowledgePackCodec().catalogFromSource(
    KnowledgePackSource(
      packId: catalogJson['packId'] as String,
      packVersion: catalogJson['packVersion'] as String,
      createdAt: DateTime.parse(catalogJson['createdAt'] as String),
      categories: categories,
      markdownArticles: articles,
    ),
  );
}
