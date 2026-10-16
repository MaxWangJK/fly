import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/fly_book.dart';
import 'fly_book_codec.dart';

class FlyBookLibrary {
  FlyBookLibrary({
    required this.rootPath,
    required this.contentKey,
    required this.publicKey,
  });
  final String? rootPath;
  final List<int> contentKey, publicKey;
  final _codec = FlyBookCodec();
  Future<void> _imports = Future.value();
  bool get ready =>
      rootPath != null && contentKey.length == 32 && publicKey.length == 32;
  String get directory => p.join(rootPath!, 'knowledge', 'books');

  Future<List<FlyBook>> load() async {
    if (rootPath == null) return [];
    final folder = Directory(directory);
    if (!await folder.exists()) return [];
    final books = <FlyBook>[];
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.fly')) continue;
      if (await entity.length() > FlyBookCodec.maxFileBytes) {
        throw const FormatException('已导入的书籍超过大小限制。');
      }
      final book = await _codec.decode(
        await entity.readAsBytes(),
        contentKey: contentKey,
        publicKey: publicKey,
      );
      if (p.basename(entity.path) != '${book.id}.fly') {
        throw const FormatException('书籍身份与文件不一致。');
      }
      books.add(book);
    }
    books.sort((a, b) => a.title.compareTo(b.title));
    return books;
  }

  Future<FlyBook> importFile(String path) {
    final result = _imports.then((_) => _import(path));
    _imports = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<FlyBook> _import(String path) async {
    if (!ready) throw const FormatException('请先配置数据目录并使用支持书籍的阅读器版本。');
    final source = File(path);
    if (await source.length() > FlyBookCodec.maxFileBytes) {
      throw const FormatException('书籍文件过大。');
    }
    final bytes = await source.readAsBytes();
    final book = await _codec.decode(
      bytes,
      contentKey: contentKey,
      publicKey: publicKey,
    );
    final folder = Directory(directory);
    await folder.create(recursive: true);
    final active = File(p.join(directory, '${book.id}.fly'));
    if (await active.exists()) {
      final previous = await _codec.decode(
        await active.readAsBytes(),
        contentKey: contentKey,
        publicKey: publicKey,
      );
      if (book.version <= previous.version) {
        throw const FormatException('此书籍版本已导入，请选择更高版本。');
      }
    }
    final suffix = const Uuid().v4();
    final staged = File(p.join(directory, '.$suffix.importing'));
    final backup = File(p.join(directory, '.$suffix.previous'));
    var moved = false;
    try {
      await staged.writeAsBytes(bytes, flush: true);
      if (await active.exists()) {
        await active.rename(backup.path);
        moved = true;
      }
      await staged.rename(active.path);
    } catch (_) {
      if (moved && !await active.exists() && await backup.exists()) {
        await backup.rename(active.path);
      }
      rethrow;
    } finally {
      if (await staged.exists()) await staged.delete();
      if (await backup.exists() && await active.exists()) await backup.delete();
    }
    return book;
  }
}

class FlyReadingEntry {
  const FlyReadingEntry({
    required this.bookId,
    required this.chapterId,
    required this.position,
    required this.furthest,
    required this.at,
  });
  final String bookId, chapterId;
  final double position, furthest;
  final DateTime at;
  String get key => '$bookId/$chapterId';
  Map<String, Object> toJson() => {
    'book': bookId,
    'chapter': chapterId,
    'position': position,
    'furthest': furthest,
    'at': at.toUtc().toIso8601String(),
  };
}

class FlyReadingState {
  const FlyReadingState({this.entries = const []});
  final List<FlyReadingEntry> entries;
  FlyReadingEntry? chapter(String book, String chapter) => entries
      .where((e) => e.bookId == book && e.chapterId == chapter)
      .firstOrNull;
  FlyReadingEntry? last(String book) =>
      entries.where((e) => e.bookId == book).firstOrNull;
  double progress(FlyBook book) =>
      book.chapters
          .map((c) => chapter(book.id, c.id)?.furthest ?? 0)
          .fold<double>(0, (a, b) => a + b) /
      book.chapters.length;
}

/// Personal reading state shares the existing DB/backup but is device-local.
class FlyReadingRepository {
  FlyReadingRepository(this.db);
  final AppDatabase db;
  static const key = 'bookReader.progress';
  Future<void> _writes = Future.value();

  Future<FlyReadingState> load() async {
    final row = await (db.select(
      db.appSettings,
    )..where((r) => r.key.equals(key))).getSingleOrNull();
    if (row == null) return const FlyReadingState();
    try {
      final data = jsonDecode(row.value);
      if (data is! List) return const FlyReadingState();
      final entries = <FlyReadingEntry>[];
      for (final item in data.take(2048)) {
        if (item is! Map ||
            item['book'] is! String ||
            item['chapter'] is! String ||
            item['position'] is! num ||
            item['furthest'] is! num ||
            item['at'] is! String) {
          continue;
        }
        final at = DateTime.tryParse(item['at'] as String);
        final position = (item['position'] as num).toDouble();
        final furthest = (item['furthest'] as num).toDouble();
        if (at == null || !position.isFinite || !furthest.isFinite) continue;
        entries.add(
          FlyReadingEntry(
            bookId: item['book'] as String,
            chapterId: item['chapter'] as String,
            position: position.clamp(0, 1),
            furthest: furthest.clamp(0, 1),
            at: at,
          ),
        );
      }
      entries.sort((a, b) => b.at.compareTo(a.at));
      return FlyReadingState(entries: entries);
    } on FormatException {
      return const FlyReadingState();
    }
  }

  Future<void> record(String book, String chapter, double position) {
    if (!FlyBook.validId(book) ||
        !FlyBook.validId(chapter) ||
        !position.isFinite) {
      return Future.error(const FormatException('Invalid reading position'));
    }
    final result = _writes.then((_) async {
      final state = await load();
      final value = position.clamp(0.0, 1.0);
      final old = state.chapter(book, chapter);
      final entry = FlyReadingEntry(
        bookId: book,
        chapterId: chapter,
        position: value,
        furthest: old != null && old.furthest > value ? old.furthest : value,
        at: DateTime.now(),
      );
      final entries = [
        entry,
        ...state.entries.where((e) => e.key != entry.key),
      ].take(2048).toList();
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: key,
              value: jsonEncode(entries.map((e) => e.toJson()).toList()),
              updatedAt: DateTime.now(),
            ),
          );
    });
    _writes = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
