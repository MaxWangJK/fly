import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../../core/storage/data_root_providers.dart';
import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../data/knowledge_developer_repository.dart';
import '../data/knowledge_markdown_compiler.dart';
import '../data/knowledge_pack_codec.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_html_document.dart';
import 'knowledge_html_viewer.dart';

const enableKnowledgeEditor = bool.fromEnvironment(
  'ENABLE_KNOWLEDGE_EDITOR',
  defaultValue: false,
);

/// Developer-only authoring. Signing key is selected on export, never saved.
class KnowledgeDeveloperDialog extends ConsumerStatefulWidget {
  const KnowledgeDeveloperDialog({super.key});

  @override
  ConsumerState<KnowledgeDeveloperDialog> createState() =>
      _KnowledgeDeveloperDialogState();
}

class _KnowledgeDeveloperDialogState
    extends ConsumerState<KnowledgeDeveloperDialog> {
  KnowledgeDeveloperRepository? repository;
  KnowledgePackSource? source;
  final markdown = TextEditingController();
  final version = TextEditingController();
  String? selectedId;
  String? selectedCategory;
  String? error;
  String? status;
  bool busy = false;
  bool preview = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    final root = ref.read(dataRootPathProvider);
    if (root == null) {
      setState(() => error = 'FlyData unavailable');
      return;
    }
    repository = KnowledgeDeveloperRepository(root);
    try {
      final next = await repository!.load();
      if (!mounted) return;
      setState(() {
        source = next;
        version.text = next.packVersion;
        selectedId = next.markdownArticles.keys.firstOrNull;
        if (selectedId != null) {
          markdown.text = next.markdownArticles[selectedId]!;
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    markdown.dispose();
    version.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      status = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  KnowledgePackSource edited() {
    final current = source!;
    final currentId = selectedId;
    final articles = {...current.markdownArticles};
    if (currentId != null) {
      final parsed = KnowledgeSource.parse(markdown.text);
      if (parsed.frontMatter['id'] != currentId) {
        throw const FormatException('Changing an article ID is not supported');
      }
      articles['articles/$currentId.md'] = markdown.text;
    }
    return KnowledgePackSource(
      packId: current.packId,
      packVersion: version.text.trim(),
      createdAt: current.createdAt,
      categories: current.categories,
      markdownArticles: articles,
      assets: current.assets,
    );
  }

  Future<void> save() => run(() async {
    final next = edited();
    await repository!.save(next);
    if (mounted) {
      setState(() {
        source = next;
        status = context.l10n.t('knowledgeSave');
      });
    }
  });

  void select(String id) {
    if (id == selectedId) return;
    // Never discard an unsaved draft on selection.
    if (selectedId != null &&
        markdown.text != source!.markdownArticles['articles/$selectedId.md']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.isZh ? '请先保存当前文章' : 'Save the current article first',
          ),
        ),
      );
      return;
    }
    setState(() {
      selectedId = id;
      markdown.text = source!.markdownArticles['articles/$id.md'] ?? '';
      preview = false;
    });
  }

  Future<String?> ask(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (value) => Navigator.pop(dialog, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, controller.text.trim()),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> newCategory() async {
    final title = await ask(context.l10n.t('knowledgeNewCategory'));
    if (title == null || title.isEmpty || source == null) return;
    await run(() async {
      final now = DateTime.now().microsecondsSinceEpoch;
      final category = KnowledgeCategory(
        id: 'category-$now',
        slug: 'category-$now',
        titleZh: title,
        titleEn: title,
        parentId: selectedCategory,
        sortOrder: source!.categories.length + 1,
      );
      final next = KnowledgeDeveloperRepository.withCategories(source!, [
        ...source!.categories,
        category,
      ]);
      await repository!.save(next);
      if (mounted) {
        setState(() {
          source = next;
          selectedCategory = category.id;
        });
      }
    });
  }

  Future<void> renameCategory(KnowledgeCategory category) async {
    final title = await ask(
      context.l10n.isZh ? '重命名目录' : 'Rename category',
      initial: category.title(context.l10n.isZh),
    );
    if (title == null || title.isEmpty) return;
    await run(() async {
      final next = KnowledgeDeveloperRepository.withCategories(source!, [
        for (final value in source!.categories)
          value.id == category.id
              ? KnowledgeCategory(
                  id: value.id,
                  slug: value.slug,
                  titleZh: title,
                  titleEn: title,
                  parentId: value.parentId,
                  sortOrder: value.sortOrder,
                  icon: value.icon,
                )
              : value,
      ]);
      await repository!.save(next);
      if (mounted) setState(() => source = next);
    });
  }

  Future<void> moveCategory(KnowledgeCategory category, int direction) =>
      run(() async {
        final siblings =
            source!.categories
                .where((item) => item.parentId == category.parentId)
                .toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        final index = siblings.indexWhere((item) => item.id == category.id);
        final target = index + direction;
        if (target < 0 || target >= siblings.length) return;
        final moved = siblings.removeAt(index);
        siblings.insert(target, moved);
        final order = {
          for (var i = 0; i < siblings.length; i++) siblings[i].id: i,
        };
        final next = KnowledgeDeveloperRepository.withCategories(source!, [
          for (final item in source!.categories)
            KnowledgeCategory(
              id: item.id,
              slug: item.slug,
              titleZh: item.titleZh,
              titleEn: item.titleEn,
              parentId: item.parentId,
              icon: item.icon,
              sortOrder: order[item.id] ?? item.sortOrder,
            ),
        ]);
        await repository!.save(next);
        if (mounted) setState(() => source = next);
      });

  Future<void> newArticle() async {
    final title = await ask(context.l10n.t('knowledgeNewArticle'));
    if (title == null || title.isEmpty || source == null) return;
    await run(() async {
      final id = 'article-${DateTime.now().microsecondsSinceEpoch}';
      final category = selectedCategory ?? source!.categories.first.id;
      final text =
          '''---
id: $id
slug: $id
title: $title
summary:
category: $category
tags:
keywords:
sortOrder: 1
isFeatured: false
accessLevel: free
copyPolicy: none
locale: zh-CN
version: 1
updatedAt: ${DateTime.now().toUtc().toIso8601String()}
---

# $title

写下正文。
''';
      final next = KnowledgeDeveloperRepository.withArticle(source!, text);
      await repository!.save(next);
      if (mounted) {
        setState(() {
          source = next;
          selectedId = id;
          markdown.text = text;
          preview = false;
        });
      }
    });
  }

  Future<void> insertImage([Uint8List? raw]) async {
    if (source == null || selectedId == null) return;
    raw ??= await () async {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Image',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
      return file == null ? null : File(file.path).readAsBytes();
    }();
    if (raw == null) return;
    await run(() async {
      final decoder = await ui.instantiateImageCodec(raw!, targetWidth: 1600);
      final frame = await decoder.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      decoder.dispose();
      if (data == null) throw StateError('Image conversion failed');
      final bytes = data.buffer.asUint8List();
      if (bytes.length > 8 * 1024 * 1024) {
        throw StateError('Image exceeds 8 MB');
      }
      final path =
          'assets/images/$selectedId-${DateTime.now().microsecondsSinceEpoch}.png';
      final next = KnowledgeDeveloperRepository.withAsset(
        edited(),
        path,
        bytes,
      );
      final inserted = '\n![说明]($path)\n';
      final selection = markdown.selection;
      final start = selection.isValid ? selection.start : markdown.text.length;
      markdown.text = markdown.text.replaceRange(start, start, inserted);
      markdown.selection = TextSelection.collapsed(
        offset: start + inserted.length,
      );
      final saved = KnowledgeDeveloperRepository.withArticle(
        next,
        markdown.text,
      );
      await repository!.save(saved);
      if (mounted) {
        setState(() {
          source = saved;
          status = path;
        });
      }
    });
  }

  Future<void> pasteImage() async {
    final bytes = await Pasteboard.image;
    if (bytes == null) return;
    await insertImage(bytes);
  }

  Future<void> export() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Ed25519 signing seed',
          extensions: ['key', 'txt'],
        ),
      ],
    );
    if (file == null) return;
    await run(() async {
      final text = (await File(file.path).readAsString()).trim();
      final seed = base64Url.decode(base64Url.normalize(text));
      if (seed.length != 32) {
        throw const FormatException('Expected 32-byte Ed25519 seed');
      }
      final next = edited();
      final path = await repository!.export(next, signingSeed: seed);
      if (mounted) setState(() => status = path);
    });
  }

  Widget previewPanel() {
    try {
      final draft = edited();
      final catalog = KnowledgePackCodec().catalogFromSource(draft);
      final article = catalog.article(selectedId!);
      if (article == null) return const Center(child: Text('Article missing'));
      return KnowledgeHtmlViewer(
        html: knowledgeHtmlDocument(
          article: article,
          colors: context.flyColors,
        ),
        onLink: (_) {},
        onImage: (_) {},
      );
    } catch (e) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(20), child: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = source;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 1280,
        height: 800,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(
                    context.l10n.t('knowledgeDeveloper'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: version,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: context.l10n.t('knowledgeVersion'),
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: busy || draft == null ? null : save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(context.l10n.t('knowledgeSave')),
                  ),
                  TextButton.icon(
                    onPressed: busy || draft == null ? null : export,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: Text(context.l10n.t('knowledgeExport')),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (status != null) Text(status!),
            const Divider(height: 1),
            Expanded(
              child: draft == null
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        SizedBox(
                          width: 240,
                          child: Column(
                            children: [
                              Wrap(
                                children: [
                                  IconButton(
                                    tooltip: context.l10n.t(
                                      'knowledgeNewCategory',
                                    ),
                                    onPressed: newCategory,
                                    icon: const Icon(
                                      Icons.create_new_folder_outlined,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: context.l10n.t(
                                      'knowledgeNewArticle',
                                    ),
                                    onPressed: newArticle,
                                    icon: const Icon(Icons.note_add_outlined),
                                  ),
                                ],
                              ),
                              Expanded(
                                child: ListView(
                                  children: [
                                    for (final category in draft.categories)
                                      ListTile(
                                        dense: true,
                                        selected:
                                            selectedCategory == category.id,
                                        title: Text(
                                          '${category.parentId == null ? '' : '  ↳ '}${category.title(context.l10n.isZh)}',
                                        ),
                                        onTap: () => setState(
                                          () => selectedCategory = category.id,
                                        ),
                                        trailing: PopupMenuButton<String>(
                                          onSelected: (value) {
                                            if (value == 'rename') {
                                              renameCategory(category);
                                            } else if (value == 'up') {
                                              moveCategory(category, -1);
                                            } else if (value == 'down') {
                                              moveCategory(category, 1);
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'rename',
                                              child: Text('Rename'),
                                            ),
                                            PopupMenuItem(
                                              value: 'up',
                                              child: Text('Move up'),
                                            ),
                                            PopupMenuItem(
                                              value: 'down',
                                              child: Text('Move down'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    const Divider(),
                                    for (final entry
                                        in draft.markdownArticles.entries)
                                      ListTile(
                                        dense: true,
                                        selected:
                                            selectedId ==
                                            KnowledgeSource.parse(entry.value)
                                                .frontMatter['id'],
                                        title: Text(
                                          KnowledgeSource.parse(entry.value)
                                                  .frontMatter['title'] ??
                                              entry.key,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: () => select(
                                          KnowledgeSource.parse(entry.value)
                                              .frontMatter['id']!,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  children: [
                                    SegmentedButton<bool>(
                                      segments: [
                                        ButtonSegment(
                                          value: false,
                                          label: Text(
                                            context.l10n.t('knowledgeSource'),
                                          ),
                                        ),
                                        ButtonSegment(
                                          value: true,
                                          label: Text(
                                            context.l10n.t('knowledgePreview'),
                                          ),
                                        ),
                                      ],
                                      selected: {preview},
                                      onSelectionChanged: (value) =>
                                          setState(() => preview = value.first),
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: selectedId == null
                                          ? null
                                          : () => insertImage(),
                                      icon: const Icon(Icons.image_outlined),
                                      label: Text(
                                        context.l10n.t('knowledgeInsertImage'),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: selectedId == null
                                          ? null
                                          : pasteImage,
                                      icon: const Icon(Icons.paste_outlined),
                                      label: Text(
                                        context.l10n.t('knowledgePasteImage'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: selectedId == null
                                    ? const SizedBox.shrink()
                                    : preview
                                    ? previewPanel()
                                    : Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Focus(
                                          onKeyEvent: (node, event) {
                                            if (event is KeyDownEvent &&
                                                HardwareKeyboard
                                                    .instance
                                                    .isControlPressed &&
                                                event.logicalKey ==
                                                    LogicalKeyboardKey.keyV) {
                                              pasteImage();
                                            }
                                            return KeyEventResult.ignored;
                                          },
                                          child: TextField(
                                            controller: markdown,
                                            expands: true,
                                            minLines: null,
                                            maxLines: null,
                                            textAlignVertical:
                                                TextAlignVertical.top,
                                            style: const TextStyle(
                                              fontFamily: 'Consolas',
                                              fontSize: 14,
                                              height: 1.5,
                                            ),
                                            decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
