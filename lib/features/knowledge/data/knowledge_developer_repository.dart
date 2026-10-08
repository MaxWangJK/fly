import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../domain/knowledge_models.dart';
import 'knowledge_markdown_compiler.dart';
import 'knowledge_pack_codec.dart';
import 'knowledge_repository.dart';

/// Developer drafts live outside the signed consumer content and personal notes.
class KnowledgeDeveloperRepository {
  KnowledgeDeveloperRepository(this.rootPath);

  final String rootPath;
  String get draftPath => p.join(rootPath, 'knowledge', 'developer');
  String get exportPath => p.join(rootPath, 'dist', 'knowledge');

  Future<KnowledgePackSource> load() async {
    final folder = Directory(draftPath);
    if (!await folder.exists()) {
      final seed = await loadBundledKnowledge();
      final source = KnowledgePackSource(
        packId: seed.packId,
        packVersion: seed.packVersion,
        createdAt: seed.createdAt,
        categories: seed.categories,
        markdownArticles: {
          for (final article in seed.articles)
            'articles/${article.id}.md': article.markdown,
        },
        assets: {
          for (final entry in seed.assetBytes.entries)
            entry.key: Uint8List.fromList(entry.value),
        },
      );
      await save(source);
      return source;
    }
    final categoryFile = File(p.join(draftPath, 'categories.json'));
    final metadataFile = File(p.join(draftPath, 'draft.json'));
    final categories = (jsonDecode(await categoryFile.readAsString()) as List)
        .map(
          (item) => KnowledgeCategory.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    final metadata =
        jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
    final articles = <String, String>{};
    final assets = <String, Uint8List>{};
    await for (final entry in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is! File) continue;
      final path = p
          .relative(entry.path, from: draftPath)
          .replaceAll('\\', '/');
      if (path.startsWith('articles/') && path.endsWith('.md')) {
        articles[path] = await entry.readAsString();
      } else if (path.startsWith('assets/')) {
        assets[path] = await entry.readAsBytes();
      }
    }
    return KnowledgePackSource(
      packId: metadata['packId'] as String,
      packVersion: metadata['packVersion'] as String,
      createdAt: DateTime.parse(metadata['createdAt'] as String),
      categories: categories,
      markdownArticles: articles,
      assets: assets,
    );
  }

  Future<void> save(KnowledgePackSource source) async {
    // Validate the whole snapshot before changing a published draft.
    KnowledgePackCodec().catalogFromSource(source);
    final folder = Directory(draftPath);
    await folder.create(recursive: true);
    await _atomicWrite(
      p.join(folder.path, 'draft.json'),
      utf8.encode(
        jsonEncode({
          'packId': source.packId,
          'packVersion': source.packVersion,
          'createdAt': source.createdAt.toUtc().toIso8601String(),
        }),
      ),
    );
    await _atomicWrite(
      p.join(folder.path, 'categories.json'),
      utf8.encode(
        jsonEncode(source.categories.map((c) => c.toJson()).toList()),
      ),
    );
    for (final entry in source.markdownArticles.entries) {
      await _atomicWrite(
        p.joinAll([folder.path, ...entry.key.split('/')]),
        utf8.encode(entry.value),
      );
    }
    for (final entry in source.assets.entries) {
      await _atomicWrite(
        p.joinAll([folder.path, ...entry.key.split('/')]),
        entry.value,
      );
    }
  }

  Future<void> _atomicWrite(String path, List<int> bytes) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    final temporary = File('$path.pending');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(path);
  }

  Future<String> export(
    KnowledgePackSource source, {
    required List<int> signingSeed,
  }) async {
    KnowledgePackCodec().catalogFromSource(source);
    final bytes = await KnowledgePackCodec().export(
      source,
      signingSeed: signingSeed,
    );
    final folder = Directory(exportPath);
    await folder.create(recursive: true);
    final version = source.packVersion.replaceAll(
      RegExp(r'[^a-zA-Z0-9.-]'),
      '-',
    );
    final file = File(p.join(folder.path, 'Fly-Knowledge-$version.flykb'));
    await _atomicWrite(file.path, bytes);
    return file.path;
  }

  static KnowledgePackSource withArticle(
    KnowledgePackSource original,
    String markdown,
  ) {
    final article = KnowledgeSource.parse(markdown);
    final id = article.frontMatter['id']!;
    final articles = {
      ...original.markdownArticles,
      'articles/$id.md': markdown,
    };
    return KnowledgePackSource(
      packId: original.packId,
      packVersion: original.packVersion,
      createdAt: original.createdAt,
      categories: original.categories,
      markdownArticles: articles,
      assets: original.assets,
    );
  }

  static KnowledgePackSource withCategories(
    KnowledgePackSource original,
    List<KnowledgeCategory> categories,
  ) => KnowledgePackSource(
    packId: original.packId,
    packVersion: original.packVersion,
    createdAt: original.createdAt,
    categories: categories,
    markdownArticles: original.markdownArticles,
    assets: original.assets,
  );

  static KnowledgePackSource withAsset(
    KnowledgePackSource original,
    String path,
    Uint8List bytes,
  ) => KnowledgePackSource(
    packId: original.packId,
    packVersion: original.packVersion,
    createdAt: original.createdAt,
    categories: original.categories,
    markdownArticles: original.markdownArticles,
    assets: {...original.assets, path: bytes},
  );
}
