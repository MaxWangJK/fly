import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../data/fly_book_repository.dart';
import '../domain/fly_book.dart';
import 'fly_book_document.dart';
import 'fly_book_providers.dart';

class FlyBookWorkspace extends ConsumerStatefulWidget {
  const FlyBookWorkspace({this.initialChapterId, super.key});
  final String? initialChapterId;
  @override
  ConsumerState<FlyBookWorkspace> createState() => _FlyBookWorkspaceState();
}

class _FlyBookWorkspaceState extends ConsumerState<FlyBookWorkspace> {
  String? bookId, chapterId;
  bool importing = false;
  String? failure;
  double restorePosition = 0;
  int _navigation = 0;
  String? document;
  bool? documentDark;
  Timer? _saveTimer;
  (String, String, double)? _pending;

  String tr(String zh, String en) => context.l10n.isZh ? zh : en;

  Future<void> _import() async {
    if (importing) return;
    setState(() {
      importing = true;
      failure = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Fly Book', extensions: ['fly']),
        ],
      );
      if (file == null) return;
      final book = await ref.read(flyBookLibraryProvider).importFile(file.path);
      ref.invalidate(flyBooksProvider);
      if (!mounted) return;
      setState(() {
        bookId = book.id;
        chapterId = null;
        document = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('已导入《${book.title}》', 'Imported ${book.title}')),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => failure = tr(
            '导入失败，现有书籍保留：$error',
            'Import failed; existing books are preserved: $error',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _flush() async {
    _saveTimer?.cancel();
    final value = _pending;
    _pending = null;
    if (value == null) return;
    try {
      await ref
          .read(flyReadingRepositoryProvider)
          .record(value.$1, value.$2, value.$3);
      if (mounted) ref.invalidate(flyReadingStateProvider);
    } catch (_) {
      if (mounted) {
        setState(
          () => failure = tr(
            '阅读进度保存失败，请重试。',
            'Reading progress could not be saved.',
          ),
        );
      }
    }
  }

  void _progress(FlyBook book, FlyBookChapter chapter, double value) {
    if (bookId != book.id || chapterId != chapter.id) return;
    _pending = (book.id, chapter.id, value);
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_flush()),
    );
  }

  Future<void> _open(
    FlyBook book,
    FlyBookChapter chapter,
    FlyReadingState state,
  ) async {
    final generation = ++_navigation;
    await _flush();
    final current = await ref.read(flyReadingRepositoryProvider).load();
    if (!mounted || generation != _navigation) return;
    final position = current.chapter(book.id, chapter.id)?.position ?? 0;
    setState(() {
      bookId = book.id;
      chapterId = chapter.id;
      restorePosition = position;
      document = null;
      failure = null;
    });
    _pending = (book.id, chapter.id, position);
    await _flush();
  }

  Future<void> _history(List<FlyBook> books, FlyReadingState state) async {
    final records = state.entries
        .where(
          (entry) => books.any(
            (b) =>
                b.id == entry.bookId &&
                b.chapters.any((c) => c.id == entry.chapterId),
          ),
        )
        .take(100)
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .72,
          child: Column(
            children: [
              ListTile(
                title: Text(tr('阅读历史', 'Reading history')),
                trailing: IconButton(
                  tooltip: tr('关闭', 'Close'),
                  onPressed: () => Navigator.pop(sheet),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Text(tr('尚无阅读历史', 'No reading history yet')),
                      )
                    : ListView.builder(
                        itemCount: records.length,
                        itemBuilder: (_, index) {
                          final entry = records[index];
                          final book = books.firstWhere(
                            (b) => b.id == entry.bookId,
                          );
                          final chapter = book.chapters.firstWhere(
                            (c) => c.id == entry.chapterId,
                          );
                          return ListTile(
                            title: Text(chapter.title),
                            subtitle: Text(
                              '${book.title} · ${DateFormat('yyyy-MM-dd HH:mm').format(entry.at.toLocal())}',
                            ),
                            trailing: Text(
                              '${(entry.furthest * 100).round()}%',
                            ),
                            onTap: () {
                              Navigator.pop(sheet);
                              unawaited(_open(book, chapter, state));
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    final pending = _pending;
    if (pending != null) {
      final repository = ref.read(flyReadingRepositoryProvider);
      unawaited(
        repository
            .record(pending.$1, pending.$2, pending.$3)
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flyColors;
    final books = ref.watch(flyBooksProvider);
    final state =
        ref.watch(flyReadingStateProvider).valueOrNull ??
        const FlyReadingState();
    return Material(
      color: colors.surface,
      child: Column(
        children: [
          Material(
            color: colors.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('资料库', 'Library'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('book-reading-history'),
                    tooltip: tr('阅读历史', 'Reading history'),
                    onPressed: () => _history(books.valueOrNull ?? [], state),
                    icon: const Icon(Icons.history),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('book-import'),
                    onPressed: importing ? null : _import,
                    icon: importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_upload_outlined, size: 18),
                    label: Text(
                      tr(
                        importing ? '导入中…' : '导入 .fly 书籍',
                        importing ? 'Importing…' : 'Import .fly book',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (failure != null)
            Material(
              color: colors.surface,
              child: ListTile(
                dense: true,
                title: Text(
                  failure!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                trailing: IconButton(
                  onPressed: () => setState(() => failure = null),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          Expanded(
            child: books.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('书籍读取失败：$error', 'Could not read books: $error')),
                      TextButton(
                        onPressed: () => ref.invalidate(flyBooksProvider),
                        child: Text(tr('重试', 'Retry')),
                      ),
                    ],
                  ),
                ),
              ),
              data: (values) => _content(values, state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(List<FlyBook> books, FlyReadingState state) {
    if (books.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_stories_outlined, size: 52),
              const SizedBox(height: 18),
              Text(
                tr('把一本外贸书，放进工作台', 'Bring a trade book into your workspace'),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  '从右上角导入 .fly 书籍，按章节阅读。阅读进度与历史会自动保存在本机。',
                  'Import a .fly book above. Read by chapter; progress and history are saved on this device.',
                ),
                textAlign: TextAlign.center,
              ),
              if (!ref.read(flyBookLibraryProvider).ready)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    tr(
                      '此构建未配置书籍阅读密钥，请使用本次提供的阅读器版本。',
                      'This build has no book key. Use the supplied reader build.',
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final selectedBook = books.where((b) => b.id == bookId).firstOrNull;
    final selectedChapter = selectedBook?.chapters
        .where((c) => c.id == chapterId)
        .firstOrNull;
    final sidebar = _sidebar(books, state);
    final viewer = selectedBook != null && selectedChapter != null
        ? _reader(selectedBook, selectedChapter, state)
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [for (final book in books) _card(book, state)],
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 840) {
          return Column(
            children: [
              ListTile(
                dense: true,
                leading: IconButton(
                  tooltip: tr('书籍目录', 'Contents'),
                  icon: const Icon(Icons.menu_book),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (sheet) => SafeArea(
                      child: SizedBox(
                        height: MediaQuery.sizeOf(sheet).height * .8,
                        child: _sidebar(
                          books,
                          state,
                          close: () => Navigator.pop(sheet),
                        ),
                      ),
                    ),
                  ),
                ),
                title: Text(
                  selectedChapter?.title ?? tr('我的书籍', 'My books'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: selectedChapter == null
                    ? null
                    : IconButton(
                        tooltip: tr('返回书架', 'Library'),
                        onPressed: () => setState(() {
                          chapterId = null;
                          document = null;
                        }),
                        icon: const Icon(Icons.arrow_back),
                      ),
              ),
              Expanded(child: viewer),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 260, child: sidebar),
            VerticalDivider(width: 1, color: context.flyColors.divider),
            Expanded(child: viewer),
          ],
        );
      },
    );
  }

  Widget _sidebar(
    List<FlyBook> books,
    FlyReadingState state, {
    VoidCallback? close,
  }) => Material(
    color: context.flyColors.secondarySidebar,
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
          child: Text(
            tr('书籍目录', 'Contents'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        for (final book in books) ...[
          ListTile(
            key: ValueKey('book-${book.id}'),
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(book.title),
            subtitle: Text(
              tr(
                '阅读 ${(state.progress(book) * 100).round()}%',
                '${(state.progress(book) * 100).round()}% read',
              ),
            ),
            selected: bookId == book.id,
            onTap: () {
              setState(() {
                bookId = book.id;
                chapterId = null;
                document = null;
              });
              close?.call();
            },
          ),
          for (var i = 0; i < book.chapters.length; i++)
            ListTile(
              key: ValueKey('book-chapter-${book.id}-${book.chapters[i].id}'),
              contentPadding: const EdgeInsets.only(left: 36, right: 12),
              dense: true,
              selected: bookId == book.id && chapterId == book.chapters[i].id,
              title: Text(
                '${(i + 1).toString().padLeft(2, '0')}  ${book.chapters[i].title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing:
                  (state.chapter(book.id, book.chapters[i].id)?.furthest ??
                          0) >=
                      .98
                  ? const Icon(Icons.check_circle_outline, size: 16)
                  : null,
              onTap: () {
                close?.call();
                unawaited(_open(book, book.chapters[i], state));
              },
            ),
          const Divider(),
        ],
      ],
    ),
  );

  Widget _card(FlyBook book, FlyReadingState state) {
    final last = state.last(book.id);
    final chapter =
        book.chapters.where((c) => c.id == last?.chapterId).firstOrNull ??
        book.chapters.first;
    final progress = state.progress(book);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${book.author} · ${book.chapters.length} ${tr('章', 'chapters')} · v${book.version}',
            ),
            const SizedBox(height: 16),
            Text(book.description),
            const SizedBox(height: 18),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              tr(
                '阅读进度 ${(progress * 100).round()}%',
                '${(progress * 100).round()}% read',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: ValueKey('book-continue-${book.id}'),
              onPressed: () => _open(book, chapter, state),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                tr(
                  last == null ? '开始阅读' : '继续阅读',
                  last == null ? 'Start reading' : 'Continue reading',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reader(FlyBook book, FlyBookChapter chapter, FlyReadingState state) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (document == null || documentDark != dark) {
      document = FlyBookDocument.render(
        book,
        chapter,
        position:
            state.chapter(book.id, chapter.id)?.position ?? restorePosition,
        dark: dark,
      );
      documentDark = dark;
    }
    final index = book.chapters.indexOf(chapter);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: tr('上一章', 'Previous chapter'),
                onPressed: index == 0
                    ? null
                    : () => _open(book, book.chapters[index - 1], state),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${index + 1}/${book.chapters.length} · ${chapter.title}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: tr('标记本章已读', 'Mark chapter read'),
                onPressed: () {
                  _progress(book, chapter, 1);
                  unawaited(_flush());
                },
                icon: const Icon(Icons.check_circle_outline),
              ),
              IconButton(
                tooltip: tr('下一章', 'Next chapter'),
                onPressed: index == book.chapters.length - 1
                    ? null
                    : () => _open(book, book.chapters[index + 1], state),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        LinearProgressIndicator(
          value: state.chapter(book.id, chapter.id)?.furthest ?? 0,
          minHeight: 2,
        ),
        Expanded(
          child: ref.read(flyBookPageBuilderProvider)(
            document!,
            (value) => _progress(book, chapter, value),
            (link) {
              final id = link.startsWith('fly://book/')
                  ? link.substring(11)
                  : '';
              final next = book.chapters.where((c) => c.id == id).firstOrNull;
              if (next != null) unawaited(_open(book, next, state));
            },
            ValueKey('book-page-${book.id}-${chapter.id}'),
          ),
        ),
      ],
    );
  }
}
