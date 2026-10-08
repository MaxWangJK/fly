import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../data/knowledge_markdown_compiler.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_html_document.dart';
import 'knowledge_html_viewer.dart';

class KnowledgeArticleView extends StatelessWidget {
  const KnowledgeArticleView({
    required this.article,
    required this.catalog,
    required this.isFavorite,
    required this.onFavorite,
    this.onNote,
    required this.onArticle,
    super.key,
  });
  final KnowledgeArticle article;
  final KnowledgeCatalog catalog;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback? onNote;
  final ValueChanged<KnowledgeArticle> onArticle;

  Future<void> _link(BuildContext context, String target) async {
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    if (uri.scheme == 'fly' &&
        uri.host == 'knowledge' &&
        uri.pathSegments.length == 1) {
      final key = uri.pathSegments.single;
      for (final related in catalog.articles) {
        if (related.slug == key || related.id == key) {
          onArticle(related);
          return;
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('knowledgeUnavailable'))),
        );
      }
    } else if (uri.scheme == 'https' && uri.host.isNotEmpty) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewerKey = GlobalKey<KnowledgeHtmlViewerState>();
    final colors = context.flyColors;
    final text = context.l10n.t;
    final rendered = KnowledgeMarkdownCompiler().compile(
      KnowledgeSource.parse(article.markdown).body,
      assets: catalog.assetBytes,
    );
    final html = knowledgeHtmlDocument(article: article, colors: colors);
    final isNew = DateTime.now().difference(article.updatedAt).inDays < 7;
    return Column(
      children: [
        Container(
          color: colors.surface,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (isNew)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.selected,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        text('knowledgeNew'),
                        style: TextStyle(fontSize: 11, color: colors.accent),
                      ),
                    ),
                  IconButton(
                    key: const ValueKey('knowledge-favorite'),
                    tooltip: text('knowledgeFavorites'),
                    onPressed: onFavorite,
                    icon: Icon(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: isFavorite ? colors.accent : colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                article.summary,
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 11),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final tag in article.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '#$tag',
                        style: TextStyle(fontSize: 11, color: colors.accent),
                      ),
                    ),
                  Text(
                    DateFormat.yMd(context.l10n.locale.toString())
                        .format(article.updatedAt),
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                  const SizedBox(width: 6),
                  if (onNote != null)
                    TextButton.icon(
                      key: const ValueKey('knowledge-take-note'),
                      onPressed: onNote,
                      icon: const Icon(Icons.edit_note_outlined, size: 17),
                      label: Text(text('knowledgeNote')),
                    ),
                  if (article.copyPolicy == KnowledgeCopyPolicy.full)
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: article.plainText),
                      ),
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: Text(text('knowledgeCopyFull')),
                    ),
                  if (article.copyPolicy == KnowledgeCopyPolicy.snippet &&
                      rendered.copyableSnippets.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: text('knowledgeCopySnippet'),
                      onSelected: (value) =>
                          Clipboard.setData(ClipboardData(text: value)),
                      itemBuilder: (_) => [
                        for (final snippet in rendered.copyableSnippets)
                          PopupMenuItem(
                            value: snippet,
                            child: Text(
                              snippet,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.copy_outlined, size: 16),
                            const SizedBox(width: 5),
                            Text(text('knowledgeCopySnippet')),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.divider),
        if (rendered.outline.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                for (final heading in rendered.outline)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(heading.label, maxLines: 1),
                      onPressed: () =>
                          viewerKey.currentState?.scrollTo(heading.id),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: KnowledgeHtmlViewer(
            key: viewerKey,
            html: html,
            onLink: (target) => _link(context, target),
            onImage: (dataUri) => previewKnowledgeImage(context, dataUri),
          ),
        ),
      ],
    );
  }
}
