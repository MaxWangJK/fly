import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/knowledge/data/knowledge_developer_repository.dart';
import 'package:fly/features/knowledge/data/knowledge_pack_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('developer draft saves separately and exports a signed pack', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fly-knowledge-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = KnowledgeDeveloperRepository(directory.path);
    final seed = await repository.load();
    expect(seed.markdownArticles.length, 14);
    final changed = KnowledgeDeveloperRepository.withArticle(
      seed,
      seed.markdownArticles['articles/sop-overview.md']!.replaceFirst(
        '外贸SOP总览',
        '外贸SOP总览（编辑）',
      ),
    );
    await repository.save(changed);
    expect(
      (await repository.load()).markdownArticles['articles/sop-overview.md'],
      contains('外贸SOP总览（编辑）'),
    );
    final exported = await repository.export(
      changed,
      signingSeed: List<int>.generate(32, (index) => index),
    );
    expect(await File(exported).exists(), isTrue);
    expect(exported, endsWith('.flykb'));
    expect(KnowledgePackCodec().catalogFromSource(changed).articles.length, 14);
  });
}
