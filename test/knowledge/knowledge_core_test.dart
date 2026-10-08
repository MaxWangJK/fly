import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/knowledge/data/knowledge_markdown_compiler.dart';
import 'package:fly/features/knowledge/data/knowledge_pack_codec.dart';
import 'package:fly/features/knowledge/data/knowledge_repository.dart';
import 'package:fly/features/knowledge/domain/knowledge_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled catalog has 14 original, renderable articles', () async {
    final catalog = await loadBundledKnowledge();
    expect(catalog.articles, hasLength(14));
    expect(catalog.categories.length, greaterThan(14));
    expect(catalog.articles.map((a) => a.id).toSet(), hasLength(14));
    for (final article in catalog.articles) {
      expect(article.title, isNotEmpty);
      expect(article.plainText, isNotEmpty);
      expect(article.html, contains('<h1>'));
      expect(article.isFree, isTrue);
    }
  });

  test('Markdown compiler removes executable HTML and unsafe links', () {
    final rendered = KnowledgeMarkdownCompiler().compile('''
# Safe

<script>alert(1)</script>

[bad](javascript:alert(1)) [internal](fly://knowledge/safe)

:::copyable
Hello customer
:::
''');
    expect(rendered.bodyHtml, isNot(contains('<script')));
    expect(rendered.bodyHtml, isNot(contains('javascript:')));
    expect(rendered.bodyHtml, contains('data-fly-href'));
    expect(rendered.copyableSnippets, ['Hello customer']);
  });

  test('signed pack verifies and refuses stale or tampered data', () async {
    final seed = List<int>.generate(32, (index) => index + 1);
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final key = (await pair.extractPublicKey()).bytes;
    final codec = KnowledgePackCodec();
    final source = KnowledgePackSource(
      packId: 'test',
      packVersion: '2026.10.07',
      createdAt: DateTime.utc(2026, 10, 7),
      categories: const [
        KnowledgeCategory(
          id: 'lead',
          slug: 'lead',
          titleZh: '开发客户',
          titleEn: 'Leads',
          sortOrder: 1,
        ),
      ],
      markdownArticles: {
        'articles/test.md': '''---
id: test
title: 测试文章
category: lead
slug: test
---
# 测试文章
正文内容
''',
      },
    );
    final encoded = await codec.export(source, signingSeed: seed);
    final verified = await codec.verify(
      encoded,
      publicKey: key,
      currentVersion: '2026.10.06',
    );
    expect(verified.catalog.article('test')?.title, '测试文章');
    await expectLater(
      codec.verify(encoded, publicKey: key, currentVersion: '2026.10.07'),
      throwsA(isA<KnowledgePackException>()),
    );
    final wrongKey = (await (await Ed25519().newKeyPairFromSeed(
      List<int>.filled(32, 9),
    )).extractPublicKey()).bytes;
    await expectLater(
      codec.verify(encoded, publicKey: wrongKey),
      throwsA(isA<KnowledgePackException>()),
    );
    expect(jsonEncode(verified.catalog.articles.first.tags), '[]');
  });
}
