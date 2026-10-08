enum KnowledgeCopyPolicy { none, snippet, full }

enum KnowledgeAccessLevel { free, pro }

class KnowledgeCategory {
  const KnowledgeCategory({
    required this.id,
    required this.slug,
    required this.titleZh,
    required this.titleEn,
    required this.sortOrder,
    this.parentId,
    this.icon,
  });

  final String id;
  final String slug;
  final String titleZh;
  final String titleEn;
  final String? parentId;
  final String? icon;
  final int sortOrder;

  String title(bool isZh) => isZh ? titleZh : titleEn;

  factory KnowledgeCategory.fromJson(Map<String, dynamic> json) =>
      KnowledgeCategory(
        id: _requiredString(json, 'id'),
        slug: _requiredString(json, 'slug'),
        titleZh: _requiredString(json, 'titleZh'),
        titleEn: _requiredString(json, 'titleEn'),
        parentId: json['parentId'] as String?,
        icon: json['icon'] as String?,
        sortOrder: json['sortOrder'] as int? ?? 0,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'slug': slug,
    'titleZh': titleZh,
    'titleEn': titleEn,
    'parentId': parentId,
    'icon': icon,
    'sortOrder': sortOrder,
  };
}

class KnowledgeArticle {
  const KnowledgeArticle({
    required this.id,
    required this.logicalArticleId,
    required this.categoryId,
    required this.slug,
    required this.title,
    required this.summary,
    required this.markdown,
    required this.html,
    required this.plainText,
    required this.tags,
    required this.keywords,
    required this.sortOrder,
    required this.isFeatured,
    required this.accessLevel,
    required this.copyPolicy,
    required this.locale,
    required this.version,
    required this.updatedAt,
    this.actionLink,
  });

  final String id;
  final String logicalArticleId;
  final String categoryId;
  final String slug;
  final String title;
  final String summary;
  final String markdown;
  final String html;
  final String plainText;
  final List<String> tags;
  final List<String> keywords;
  final int sortOrder;
  final bool isFeatured;
  final KnowledgeAccessLevel accessLevel;
  final KnowledgeCopyPolicy copyPolicy;
  final String locale;
  final int version;
  final DateTime updatedAt;
  final String? actionLink;

  bool get isFree => accessLevel == KnowledgeAccessLevel.free;

  KnowledgeArticle copyWith({
    String? markdown,
    String? html,
    String? plainText,
  }) => KnowledgeArticle(
    id: id,
    logicalArticleId: logicalArticleId,
    categoryId: categoryId,
    slug: slug,
    title: title,
    summary: summary,
    markdown: markdown ?? this.markdown,
    html: html ?? this.html,
    plainText: plainText ?? this.plainText,
    tags: tags,
    keywords: keywords,
    sortOrder: sortOrder,
    isFeatured: isFeatured,
    accessLevel: accessLevel,
    copyPolicy: copyPolicy,
    locale: locale,
    version: version,
    updatedAt: updatedAt,
    actionLink: actionLink,
  );
}

class KnowledgeCatalog {
  const KnowledgeCatalog({
    required this.packId,
    required this.packVersion,
    required this.createdAt,
    required this.categories,
    required this.articles,
    this.assetBytes = const {},
  });

  final String packId;
  final String packVersion;
  final DateTime createdAt;
  final List<KnowledgeCategory> categories;
  final List<KnowledgeArticle> articles;
  final Map<String, List<int>> assetBytes;

  KnowledgeArticle? article(String id) {
    for (final article in articles) {
      if (article.id == id) return article;
    }
    return null;
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid knowledge $key');
  }
  return value.trim();
}
