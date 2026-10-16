import 'dart:convert';
import 'dart:typed_data';

class FlyBookChapter {
  const FlyBookChapter({
    required this.id,
    required this.title,
    required this.html,
  });
  final String id, title, html;
  Map<String, Object> toJson() => {'id': id, 'title': title, 'html': html};
}

class FlyBook {
  const FlyBook({
    required this.id,
    required this.title,
    required this.author,
    required this.version,
    required this.description,
    required this.css,
    required this.chapters,
    this.assets = const {},
  });
  final String id, title, author, description, css;
  final int version;
  final List<FlyBookChapter> chapters;
  final Map<String, Uint8List> assets;

  static bool validId(String value) =>
      RegExp(r'^[a-z0-9][a-z0-9-]{0,79}$').hasMatch(value);
  static bool validAssetPath(String value) =>
      RegExp(r'^assets/[a-zA-Z0-9_/-]+\.(png|jpg|jpeg|webp|gif)$')
          .hasMatch(value) &&
      !value.contains('..') &&
      !value.contains('//');

  factory FlyBook.fromJson(Map<String, dynamic> data) {
    String text(Map<String, dynamic> row, String key, int limit) {
      final value = row[key];
      if (value is! String || value.length > limit) {
        throw FormatException('Invalid book $key');
      }
      return value;
    }

    final id = text(data, 'id', 80);
    final version = data['version'];
    final title = text(data, 'title', 240);
    if (!validId(id) ||
        version is! int ||
        version < 1 ||
        title.trim().isEmpty) {
      throw const FormatException('Invalid book identity');
    }
    final entries = data['chapters'];
    if (entries is! List || entries.isEmpty || entries.length > 256) {
      throw const FormatException('A book needs 1–256 chapters');
    }
    final ids = <String>{};
    final chapters = <FlyBookChapter>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid chapter');
      }
      final chapterId = text(entry, 'id', 80);
      final chapterTitle = text(entry, 'title', 240);
      if (!validId(chapterId) ||
          !ids.add(chapterId) ||
          chapterTitle.trim().isEmpty) {
        throw const FormatException('Invalid or duplicate chapter');
      }
      chapters.add(
        FlyBookChapter(
          id: chapterId,
          title: chapterTitle,
          html: text(entry, 'html', 1024 * 1024),
        ),
      );
    }
    final assetEntries = data['assets'];
    if (assetEntries is! Map<String, dynamic> || assetEntries.length > 512) {
      throw const FormatException('Invalid book assets');
    }
    final assets = <String, Uint8List>{};
    var total = 0;
    for (final entry in assetEntries.entries) {
      if (!validAssetPath(entry.key) || entry.value is! String) {
        throw const FormatException('Unsafe book asset');
      }
      final bytes = base64Decode(entry.value as String);
      total += bytes.length;
      if (bytes.length > 8 * 1024 * 1024 || total > 32 * 1024 * 1024) {
        throw const FormatException('Book image size limit exceeded');
      }
      assets[entry.key] = bytes;
    }
    return FlyBook(
      id: id,
      title: title,
      version: version,
      author: text(data, 'author', 240),
      description: text(data, 'description', 4000),
      css: text(data, 'css', 256 * 1024),
      chapters: chapters,
      assets: assets,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'version': version,
    'description': description,
    'css': css,
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'assets': {
      for (final entry in assets.entries) entry.key: base64Encode(entry.value),
    },
  };
}
