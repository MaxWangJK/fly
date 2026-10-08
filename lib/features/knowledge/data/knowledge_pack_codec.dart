import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../domain/knowledge_models.dart';
import '../../../config/app_version.dart';
import 'knowledge_markdown_compiler.dart';

class KnowledgePackException implements Exception {
  const KnowledgePackException(this.message);
  final String message;
  @override
  String toString() => message;
}

class KnowledgePackSource {
  const KnowledgePackSource({
    required this.packId,
    required this.packVersion,
    required this.createdAt,
    required this.categories,
    required this.markdownArticles,
    this.assets = const {},
  });
  final String packId;
  final String packVersion;
  final DateTime createdAt;
  final List<KnowledgeCategory> categories;
  final Map<String, String> markdownArticles;
  final Map<String, Uint8List> assets;
}

class VerifiedKnowledgePack {
  const VerifiedKnowledgePack({required this.catalog, required this.files});
  final KnowledgeCatalog catalog;
  final Map<String, Uint8List> files;
}

/// Wire format is versioned and independent of local distribution (file/cloud).
class KnowledgePackCodec {
  KnowledgePackCodec({KnowledgeMarkdownCompiler? compiler})
    : compiler = compiler ?? KnowledgeMarkdownCompiler();
  final KnowledgeMarkdownCompiler compiler;

  static const schemaVersion = 1;
  static const maxCompressedBytes = 64 * 1024 * 1024;
  static const maxExpandedBytes = 128 * 1024 * 1024;
  static final _safePath = RegExp(r'^[a-zA-Z0-9_./-]+$');

  KnowledgeCatalog catalogFromSource(KnowledgePackSource source) =>
      catalogFromFiles(
        _buildFiles(source),
        packId: source.packId,
        packVersion: source.packVersion,
        createdAt: source.createdAt,
      );

  Future<Uint8List> export(
    KnowledgePackSource source, {
    required List<int> signingSeed,
  }) async {
    if (signingSeed.length != 32) {
      throw const KnowledgePackException(
        'Ed25519 signing seed must be 32 bytes',
      );
    }
    final files = _buildFiles(source);
    final hashes = {
      for (final path in (files.keys.toList()..sort()))
        path: sha256.convert(files[path]!).toString(),
    };
    final manifest = <String, Object>{
      'packId': source.packId,
      'packVersion': source.packVersion,
      'schemaVersion': schemaVersion,
      'createdAt': source.createdAt.toUtc().toIso8601String(),
      'minimumFlyVersion': flyAppVersion.split('+').first,
      'articleCount': source.markdownArticles.length,
      'assetCount': source.assets.length,
      'contentHash': sha256
          .convert(utf8.encode(hashes.values.join('\n')))
          .toString(),
      'files': hashes,
    };
    final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    final keyPair = await Ed25519().newKeyPairFromSeed(signingSeed);
    final signature = await Ed25519().sign(manifestBytes, keyPair: keyPair);
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    archive.addFile(
      ArchiveFile(
        'signature/manifest.sig',
        signature.bytes.length,
        Uint8List.fromList(signature.bytes),
      ),
    );
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  Future<VerifiedKnowledgePack> verify(
    List<int> zipBytes, {
    required List<int> publicKey,
    String? currentVersion,
  }) async {
    if (zipBytes.length > maxCompressedBytes || publicKey.length != 32) {
      throw const KnowledgePackException('Invalid pack size or signing key');
    }
    _preflightZip(zipBytes);
    final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    final files = <String, Uint8List>{};
    var expanded = 0;
    for (final entry in archive) {
      if (!entry.isFile ||
          !_validPath(entry.name) ||
          files.containsKey(entry.name)) {
        throw const KnowledgePackException('Unsafe or duplicate pack path');
      }
      expanded += entry.size;
      if (expanded > maxExpandedBytes || entry.size < 0) {
        throw const KnowledgePackException('Pack expanded size limit exceeded');
      }
      files[entry.name] = Uint8List.fromList(entry.content as List<int>);
    }
    final manifestBytes = files.remove('manifest.json');
    final signatureBytes = files.remove('signature/manifest.sig');
    if (manifestBytes == null || signatureBytes?.length != 64) {
      throw const KnowledgePackException('Missing signed manifest');
    }
    final valid = await Ed25519().verify(
      manifestBytes,
      signature: Signature(
        signatureBytes!,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) throw const KnowledgePackException('Invalid pack signature');
    final manifest = jsonDecode(utf8.decode(manifestBytes));
    if (manifest is! Map<String, dynamic> ||
        manifest['schemaVersion'] != schemaVersion ||
        manifest['packId'] is! String ||
        manifest['packVersion'] is! String ||
        manifest['files'] is! Map<String, dynamic>) {
      throw const KnowledgePackException('Unsupported pack manifest');
    }
    if (currentVersion != null &&
        compareVersions(manifest['packVersion'] as String, currentVersion) <=
            0) {
      throw const KnowledgePackException('Pack version must be newer');
    }
    if (compareVersions(
          manifest['minimumFlyVersion'] as String? ?? '0',
          flyAppVersion.split('+').first,
        ) >
        0) {
      throw const KnowledgePackException('Pack requires a newer Fly version');
    }
    final expected = manifest['files'] as Map<String, dynamic>;
    if (expected.length != files.length ||
        expected.keys.toSet().difference(files.keys.toSet()).isNotEmpty) {
      throw const KnowledgePackException(
        'Pack file list does not match manifest',
      );
    }
    final sorted = expected.keys.toList()..sort();
    for (final path in sorted) {
      if (expected[path] != sha256.convert(files[path]!).toString()) {
        throw KnowledgePackException('Pack file hash mismatch: $path');
      }
    }
    if (manifest['contentHash'] !=
        sha256
            .convert(
              utf8.encode(
                [for (final path in sorted) expected[path]].join('\n'),
              ),
            )
            .toString()) {
      throw const KnowledgePackException('Pack content hash mismatch');
    }
    final catalog = catalogFromFiles(
      files,
      packId: manifest['packId'] as String,
      packVersion: manifest['packVersion'] as String,
      createdAt: DateTime.parse(manifest['createdAt'] as String),
    );
    if (catalog.articles.length != manifest['articleCount'] ||
        catalog.assetBytes.length != manifest['assetCount']) {
      throw const KnowledgePackException('Pack content count mismatch');
    }
    return VerifiedKnowledgePack(
      catalog: catalog,
      files: {
        ...files,
        'manifest.json': manifestBytes,
        'signature/manifest.sig': signatureBytes,
      },
    );
  }

  KnowledgeCatalog catalogFromFiles(
    Map<String, Uint8List> files, {
    required String packId,
    required String packVersion,
    required DateTime createdAt,
  }) {
    final categoriesBytes = files['categories.json'];
    if (categoriesBytes == null) {
      throw const KnowledgePackException('Missing categories');
    }
    final decoded = jsonDecode(utf8.decode(categoriesBytes));
    if (decoded is! List) {
      throw const KnowledgePackException('Invalid categories');
    }
    final categories = decoded
        .map(
          (item) => KnowledgeCategory.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    final categoryIds = categories.map((c) => c.id).toSet();
    if (categoryIds.length != categories.length ||
        categories.any(
          (c) => c.parentId != null && !categoryIds.contains(c.parentId),
        )) {
      throw const KnowledgePackException('Invalid category tree');
    }
    for (final category in categories) {
      final seen = <String>{};
      var current = category;
      while (current.parentId != null) {
        if (!seen.add(current.id)) {
          throw const KnowledgePackException('Category cycle');
        }
        current = categories.firstWhere((c) => c.id == current.parentId);
      }
    }
    final assets = <String, List<int>>{
      for (final entry in files.entries)
        if (entry.key.startsWith('assets/')) entry.key: entry.value,
    };
    final articles = <KnowledgeArticle>[];
    final ids = <String>{};
    for (final entry in files.entries.where(
      (e) => e.key.startsWith('articles/') && e.key.endsWith('.md'),
    )) {
      final source = KnowledgeSource.parse(utf8.decode(entry.value));
      final fields = source.frontMatter;
      final id = fields['id']!;
      if (!ids.add(id) || !categoryIds.contains(fields['category'])) {
        throw const KnowledgePackException(
          'Duplicate article or missing category',
        );
      }
      final rendered = compiler.compile(source.body, assets: assets);
      final htmlPath = 'rendered/$id.html';
      if (utf8.decode(files[htmlPath] ?? []) != rendered.bodyHtml) {
        throw KnowledgePackException('Rendered HTML mismatch: $id');
      }
      articles.add(
        KnowledgeArticle(
          id: id,
          logicalArticleId: fields['logicalArticleId'] ?? id,
          categoryId: fields['category']!,
          slug: fields['slug']!,
          title: fields['title']!,
          summary: fields['summary'] ?? '',
          markdown: utf8.decode(entry.value),
          html: rendered.bodyHtml,
          plainText: rendered.plainText,
          tags: _csv(fields['tags']),
          keywords: _csv(fields['keywords']),
          sortOrder: int.tryParse(fields['sortOrder'] ?? '') ?? 0,
          isFeatured: fields['isFeatured'] == 'true',
          accessLevel: parseAccessLevel(fields['accessLevel']),
          copyPolicy: parseCopyPolicy(fields['copyPolicy']),
          locale: fields['locale'] ?? 'zh-CN',
          version: int.tryParse(fields['version'] ?? '') ?? 1,
          updatedAt: DateTime.tryParse(fields['updatedAt'] ?? '') ?? createdAt,
          actionLink: fields['actionLink'],
        ),
      );
    }
    final searchBytes = files['search/index.json'];
    if (searchBytes == null || jsonDecode(utf8.decode(searchBytes)) is! List) {
      throw const KnowledgePackException('Invalid search index');
    }
    articles.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.title.compareTo(b.title);
    });
    return KnowledgeCatalog(
      packId: packId,
      packVersion: packVersion,
      createdAt: createdAt,
      categories: categories,
      articles: articles,
      assetBytes: assets,
    );
  }

  Map<String, Uint8List> _buildFiles(KnowledgePackSource source) {
    if (source.packId.trim().isEmpty || source.packVersion.trim().isEmpty) {
      throw const KnowledgePackException('Pack identity is required');
    }
    final files = <String, Uint8List>{
      'categories.json': Uint8List.fromList(
        utf8.encode(
          jsonEncode([
            for (final category in source.categories) category.toJson(),
          ]),
        ),
      ),
    };
    for (final entry in source.assets.entries) {
      if (!entry.key.startsWith('assets/') || !_validPath(entry.key)) {
        throw const KnowledgePackException('Unsafe asset path');
      }
      files[entry.key] = entry.value;
    }
    final search = <Map<String, Object>>[];
    for (final entry in source.markdownArticles.entries) {
      if (!_validPath(entry.key) ||
          !entry.key.startsWith('articles/') ||
          !entry.key.endsWith('.md')) {
        throw const KnowledgePackException('Unsafe article path');
      }
      final article = KnowledgeSource.parse(entry.value);
      final fields = article.frontMatter;
      final id = fields['id']!;
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(id)) {
        throw const KnowledgePackException('Unsafe article ID');
      }
      final rendered = compiler.compile(article.body, assets: source.assets);
      files[entry.key] = Uint8List.fromList(utf8.encode(entry.value));
      files['rendered/$id.html'] = Uint8List.fromList(
        utf8.encode(rendered.bodyHtml),
      );
      search.add({
        'articleId': id,
        'title': fields['title']!,
        'summary': fields['summary'] ?? '',
        'tags': _csv(fields['tags']),
        'keywords': _csv(fields['keywords']),
        'plainText': rendered.plainText,
      });
    }
    files['search/index.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode(search)),
    );
    // Run the same structural validation as import before signing.
    catalogFromFiles(
      files,
      packId: source.packId,
      packVersion: source.packVersion,
      createdAt: source.createdAt,
    );
    return files;
  }

  static bool _validPath(String path) =>
      path.isNotEmpty &&
      path.length <= 240 &&
      _safePath.hasMatch(path) &&
      !path.startsWith('/') &&
      !path.contains('..') &&
      !path.contains('//') &&
      !path.contains('\\');

  /// ZIP decoder expands in memory, so inspect central-directory sizes first.
  /// ZIP64 and multi-disk packages are intentionally unsupported.
  static void _preflightZip(List<int> bytes) {
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    int? end;
    final start = bytes.length - 22;
    for (var at = start; at >= 0 && at >= bytes.length - 65557; at--) {
      if (data.getUint32(at, Endian.little) == 0x06054b50) {
        end = at;
        break;
      }
    }
    if (end == null ||
        data.getUint16(end + 4, Endian.little) != 0 ||
        data.getUint16(end + 6, Endian.little) != 0) {
      throw const KnowledgePackException('Invalid ZIP directory');
    }
    final count = data.getUint16(end + 10, Endian.little);
    final directorySize = data.getUint32(end + 12, Endian.little);
    final directoryOffset = data.getUint32(end + 16, Endian.little);
    if (count == 0xffff ||
        count > 2000 ||
        directorySize == 0xffffffff ||
        directoryOffset == 0xffffffff ||
        directoryOffset + directorySize > end) {
      throw const KnowledgePackException('Unsupported ZIP directory');
    }
    var at = directoryOffset;
    var expanded = 0;
    for (var i = 0; i < count; i++) {
      if (at + 46 > bytes.length ||
          data.getUint32(at, Endian.little) != 0x02014b50) {
        throw const KnowledgePackException('Invalid ZIP entry');
      }
      final size = data.getUint32(at + 24, Endian.little);
      final nameLength = data.getUint16(at + 28, Endian.little);
      final extraLength = data.getUint16(at + 30, Endian.little);
      final commentLength = data.getUint16(at + 32, Endian.little);
      final next = at + 46 + nameLength + extraLength + commentLength;
      if (size == 0xffffffff ||
          next > bytes.length ||
          !_validPath(
            ascii.decode(
              bytes.sublist(at + 46, at + 46 + nameLength),
              allowInvalid: true,
            ),
          )) {
        throw const KnowledgePackException('Unsafe ZIP entry');
      }
      expanded += size;
      if (expanded > maxExpandedBytes) {
        throw const KnowledgePackException('Pack expanded size limit exceeded');
      }
      at = next;
    }
    if (at != directoryOffset + directorySize) {
      throw const KnowledgePackException('Invalid ZIP directory size');
    }
  }

  static List<String> _csv(String? value) => value == null
      ? const []
      : value
            .split(',')
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toList();

  static int compareVersions(String left, String right) {
    final a = left.split(RegExp(r'[.+-]')).map(int.tryParse).toList();
    final b = right.split(RegExp(r'[.+-]')).map(int.tryParse).toList();
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final difference =
          (i < a.length ? a[i] ?? 0 : 0) - (i < b.length ? b[i] ?? 0 : 0);
      if (difference != 0) return difference.sign;
    }
    return 0;
  }
}
