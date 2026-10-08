import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../../../shared/search/fuzzy_match.dart';
import '../../notes/presentation/note_providers.dart';
import '../../notes/presentation/notes_workspace.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_article_view.dart';
import 'knowledge_developer_dialog.dart';
import 'knowledge_providers.dart';
import 'knowledge_sop_map.dart';

class KnowledgeWorkspace extends ConsumerStatefulWidget {
  const KnowledgeWorkspace({
    this.initialArticleId,
    this.initialNoteId,
    this.showNotes = false,
    this.standalone = false,
    super.key,
  });
  final String? initialArticleId;
  final String? initialNoteId;
  final bool showNotes;
  final bool standalone;

  @override
  ConsumerState<KnowledgeWorkspace> createState() => _KnowledgeWorkspaceState();
}

class _KnowledgeWorkspaceState extends ConsumerState<KnowledgeWorkspace> {
  String mode = 'featured';
  String? categoryId;
  String? articleId;
  String query = '';
  String? tag;
  final expanded = <String>{};
  bool creatingNote = false;

  @override
  void initState() {
    super.initState();
    articleId = widget.initialArticleId;
    if (widget.showNotes || widget.initialNoteId != null) mode = 'notes';
  }

  @override
  void didUpdateWidget(covariant KnowledgeWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialArticleId != oldWidget.initialArticleId) {
      articleId = widget.initialArticleId;
      if (articleId != null) mode = 'article';
    }
    if (widget.showNotes != oldWidget.showNotes) {
      mode = widget.showNotes ? 'notes' : 'featured';
    }
  }

  void selectArticle(KnowledgeArticle article) {
    setState(() {
      articleId = article.id;
      mode = 'article';
    });
    if (!widget.standalone) {
      context.go(
        Uri(
          path: '/knowledge',
          queryParameters: {'article': article.id},
        ).toString(),
      );
    }
  }

  void selectMode(String next, [String? category]) {
    if (next == 'notes' && widget.standalone) return;
    if (next == 'notes') {
      context.go('/knowledge?view=notes');
    } else {
      setState(() {
        mode = next;
        categoryId = category;
        articleId = null;
        query = '';
        tag = null;
      });
    }
  }

  Future<void> takeNote(KnowledgeArticle article) async {
    if (creatingNote) return;
    setState(() => creatingNote = true);
    try {
      final id = await ref
          .read(noteRepositoryProvider)
          .create(
            '${article.title} · ${context.l10n.t('knowledgeNote')}',
            linkedKnowledgeArticleId: article.id,
          );
      if (mounted) {
        context.go(
          Uri(
            path: '/knowledge',
            queryParameters: {'view': 'notes', 'id': id},
          ).toString(),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => creatingNote = false);
    }
  }

  void sopSelect(KnowledgeSopNode node, KnowledgeCatalog catalog) {
    final article = node.articleId == null
        ? null
        : catalog.article(node.articleId!);
    if (article != null) {
      selectArticle(article);
    } else {
      selectMode('category', node.categoryId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (mode == 'notes') {
      return Column(
        children: [
          Material(
            color: context.flyColors.surface,
            child: ListTile(
              leading: const Icon(Icons.arrow_back_rounded),
              title: Text(context.l10n.t('knowledgeMyNotes')),
              onTap: () => context.go('/knowledge'),
            ),
          ),
          Expanded(child: NotesWorkspace(initialNoteId: widget.initialNoteId)),
        ],
      );
    }
    return ref
        .watch(knowledgeCatalogProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${context.l10n.t('knowledgeUnavailable')}: $error'),
                TextButton(
                  onPressed: () => ref.invalidate(knowledgeCatalogProvider),
                  child: Text(context.l10n.t('licenseRetryShort')),
                ),
              ],
            ),
          ),
          data: (catalog) => _content(context, catalog),
        );
  }

  Widget _content(BuildContext context, KnowledgeCatalog catalog) {
    final favorites =
        ref.watch(knowledgeFavoritesProvider).valueOrNull ?? const <String>{};
    final colors = context.flyColors;
    final isZh = context.l10n.isZh;
    final selected = articleId == null ? null : catalog.article(articleId!);
    final articles = _filteredArticles(catalog, favorites);
    final sidebar = _sidebar(context, catalog, colors);
    final list = _articleList(context, catalog, articles, colors);
    final viewer = selected != null
        ? KnowledgeArticleView(
            article: selected,
            catalog: catalog,
            isFavorite: favorites.contains(selected.id),
            onFavorite: () async {
              await ref
                  .read(knowledgeRepositoryProvider)
                  .setFavorite(selected.id, !favorites.contains(selected.id));
              ref.invalidate(knowledgeFavoritesProvider);
            },
            onNote: widget.standalone ? null : () => takeNote(selected),
            onArticle: selectArticle,
          )
        : mode == 'sop'
        ? KnowledgeSopMap(
            isZh: isZh,
            onSelect: (node) => sopSelect(node, catalog),
          )
        : _home(context, catalog, favorites);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              Material(
                color: colors.secondarySidebar,
                child: Row(
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: context.l10n.t('knowledgeTitle'),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => SafeArea(
                            child: SizedBox(height: 650, child: sidebar),
                          ),
                        ),
                        icon: const Icon(Icons.menu_rounded),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        selected?.title ?? context.l10n.t('knowledgeTitle'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (selected != null)
                      TextButton(
                        onPressed: () => setState(() => articleId = null),
                        child: Text(context.l10n.t('noteBack')),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: selected == null && mode != 'sop' && mode != 'featured'
                    ? list
                    : viewer,
              ),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 220, child: sidebar),
            VerticalDivider(width: 1, color: colors.divider),
            SizedBox(
              width: constraints.maxWidth < 1140 ? 260 : 310,
              child: list,
            ),
            VerticalDivider(width: 1, color: colors.divider),
            Expanded(
              child: ColoredBox(color: colors.surface, child: viewer),
            ),
          ],
        );
      },
    );
  }

  List<KnowledgeArticle> _filteredArticles(
    KnowledgeCatalog catalog,
    Set<String> favorites,
  ) {
    Iterable<KnowledgeArticle> result = catalog.articles;
    if (mode == 'featured' && query.trim().isEmpty) {
      result = result.where((article) => article.isFeatured);
    }
    if (mode == 'favorites') {
      result = result.where((article) => favorites.contains(article.id));
    }
    if (mode == 'category' && categoryId != null) {
      final ids = <String>{categoryId!};
      var changed = true;
      while (changed) {
        changed = false;
        for (final category in catalog.categories) {
          if (category.parentId != null &&
              ids.contains(category.parentId) &&
              ids.add(category.id)) {
            changed = true;
          }
        }
      }
      result = result.where((article) => ids.contains(article.categoryId));
    }
    if (tag != null) {
      result = result.where((article) => article.tags.contains(tag));
    }
    if (query.trim().isNotEmpty) {
      result = result.where(
        (article) => FuzzyMatch.matches(query, [
          article.title,
          article.summary,
          article.plainText,
          ...article.tags,
          ...article.keywords,
        ]),
      );
    }
    return result.toList();
  }

  Widget _sidebar(
    BuildContext context,
    KnowledgeCatalog catalog,
    FlyColorScheme colors,
  ) {
    final top = catalog.categories.where((c) => c.parentId == null).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final children = <String, List<KnowledgeCategory>>{};
    for (final category in catalog.categories.where(
      (c) => c.parentId != null,
    )) {
      children.putIfAbsent(category.parentId!, () => []).add(category);
    }
    for (final group in children.values) {
      group.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    Widget categoryRow(KnowledgeCategory category, int depth) => Padding(
      padding: EdgeInsets.only(left: depth * 15.0),
      child: ListTile(
        dense: true,
        selected: mode == 'category' && categoryId == category.id,
        leading: children.containsKey(category.id)
            ? IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  expanded.contains(category.id)
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                ),
                onPressed: () => setState(() {
                  if (!expanded.add(category.id)) expanded.remove(category.id);
                }),
              )
            : const SizedBox(
                width: 24,
                child: Icon(Icons.article_outlined, size: 16),
              ),
        title: Text(
          category.title(context.l10n.isZh),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => selectMode('category', category.id),
      ),
    );
    List<Widget> tree(KnowledgeCategory parent, int depth) => [
      categoryRow(parent, depth),
      if (expanded.contains(parent.id))
        for (final child in children[parent.id] ?? const <KnowledgeCategory>[])
          ...tree(child, depth + 1),
    ];
    Widget fixed(
      String key,
      IconData icon,
      String selectedMode,
      VoidCallback action,
    ) => ListTile(
      key: ValueKey('knowledge-sidebar-$selectedMode'),
      dense: true,
      selected: mode == selectedMode,
      leading: Icon(icon, size: 19),
      title: Text(context.l10n.t(key)),
      onTap: action,
    );
    return Material(
      color: colors.secondarySidebar,
      child: ListTileTheme(
        data: ListTileThemeData(
          selectedTileColor: colors.selected,
          selectedColor: colors.accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 10, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.t('knowledgeTitle'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (enableKnowledgeEditor && !widget.standalone)
                    IconButton(
                      tooltip: context.l10n.t('knowledgeDeveloper'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const KnowledgeDeveloperDialog(),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  fixed(
                    'knowledgeFeatured',
                    Icons.auto_awesome_outlined,
                    'featured',
                    () => selectMode('featured'),
                  ),
                  fixed(
                    'knowledgeSop',
                    Icons.account_tree_outlined,
                    'sop',
                    () => selectMode('sop'),
                  ),
                  const Divider(height: 20),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 3, 8, 7),
                    child: Text(
                      context.l10n.t('knowledgeOfficial'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  for (final category in top) ...tree(category, 0),
                  const Divider(height: 20),
                  fixed(
                    'knowledgeFavorites',
                    Icons.star_outline,
                    'favorites',
                    () => selectMode('favorites'),
                  ),
                  if (!widget.standalone)
                    fixed(
                      'knowledgeMyNotes',
                      Icons.edit_note_outlined,
                      'notes',
                      () => selectMode('notes'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _articleList(
    BuildContext context,
    KnowledgeCatalog catalog,
    List<KnowledgeArticle> articles,
    FlyColorScheme colors,
  ) {
    final allTags =
        catalog.articles.expand((article) => article.tags).toSet().toList()
          ..sort();
    return ColoredBox(
      color: colors.canvas,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            child: TextField(
              key: const ValueKey('knowledge-search'),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 19),
                hintText: context.l10n.t('knowledgeSearch'),
              ),
              onChanged: (value) => setState(() {
                query = value;
                if (value.trim().isNotEmpty) mode = 'search';
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${articles.length} ${context.l10n.t('knowledgeRead')}',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: context.l10n.t('knowledgeTags'),
                  onSelected: (value) =>
                      setState(() => tag = value.isEmpty ? null : value),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: '',
                      child: Text(context.l10n.t('knowledgeAll')),
                    ),
                    for (final value in allTags)
                      PopupMenuItem(value: value, child: Text('#$value')),
                  ],
                  icon: Icon(
                    Icons.sell_outlined,
                    size: 18,
                    color: tag == null ? colors.textSecondary : colors.accent,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: articles.isEmpty
                ? Center(child: Text(context.l10n.t('knowledgeNoArticles')))
                : ListView.builder(
                    itemCount: articles.length,
                    itemBuilder: (context, index) {
                      final article = articles[index];
                      final active = article.id == articleId;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(9, 0, 9, 8),
                        child: Material(
                          color: active ? colors.selected : colors.surface,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            key: ValueKey('knowledge-article-${article.id}'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => selectArticle(article),
                            child: Padding(
                              padding: const EdgeInsets.all(13),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    article.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    article.summary,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    article.tags
                                        .take(3)
                                        .map((tag) => '#$tag')
                                        .join('  '),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _home(
    BuildContext context,
    KnowledgeCatalog catalog,
    Set<String> favorites,
  ) {
    final colors = context.flyColors;
    final featured = catalog.articles
        .where((article) => article.isFeatured)
        .take(4)
        .toList();
    Widget tile(
      String title,
      String subtitle,
      IconData icon,
      VoidCallback tap,
    ) => Material(
      color: colors.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: colors.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.t('knowledgeTitle'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 7),
              Text(
                context.l10n.t('knowledgeIntro'),
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 18),
              TextField(
                key: const ValueKey('knowledge-home-search'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: context.l10n.t('knowledgeSearch'),
                ),
                onChanged: (value) => setState(() {
                  query = value;
                  if (value.trim().isNotEmpty) mode = 'search';
                }),
              ),
              const SizedBox(height: 28),
              tile(
                context.l10n.t('knowledgeSop'),
                context.l10n.isZh
                    ? '从线索到复购，找到当前阶段'
                    : 'From first lead to repeat order',
                Icons.account_tree_outlined,
                () => selectMode('sop'),
              ),
              const SizedBox(height: 24),
              Text(
                context.l10n.t('knowledgeFeatured'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final article in featured) ...[
                tile(
                  article.title,
                  article.summary,
                  Icons.menu_book_outlined,
                  () => selectArticle(article),
                ),
                const SizedBox(height: 9),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.star_outline, size: 17),
                    label: Text(
                      '${context.l10n.t('knowledgeFavorites')} ${favorites.length}',
                    ),
                    onPressed: () => selectMode('favorites'),
                  ),
                  if (!widget.standalone)
                    ActionChip(
                      avatar: const Icon(Icons.edit_note_outlined, size: 17),
                      label: Text(context.l10n.t('knowledgeMyNotes')),
                      onPressed: () => selectMode('notes'),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.update_outlined, size: 17),
                    label: Text(
                      '${context.l10n.t('knowledgeVersion')} ${catalog.packVersion}',
                    ),
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
