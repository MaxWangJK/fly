import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/knowledge/data/knowledge_pack_codec.dart';
import 'package:fly/features/knowledge/data/knowledge_repository.dart';
import 'package:fly/features/knowledge/domain/knowledge_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed update leaves official pack and favorites untouched', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fly-knowledge-import-',
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });
    const category = KnowledgeCategory(
      id: 'lead',
      slug: 'lead',
      titleZh: '开发',
      titleEn: 'Leads',
      sortOrder: 1,
    );
    KnowledgePackSource source(String version, String title) =>
        KnowledgePackSource(
          packId: 'official',
          packVersion: version,
          createdAt: DateTime.utc(2026, 10, 6),
          categories: const [category],
          markdownArticles: {
            'articles/test.md':
                '''---
id: test
title: $title
category: lead
slug: test
---
# $title
正文
''',
          },
        );
    final seed = source('2026.10.06', '旧版');
    final signingSeed = List<int>.generate(32, (i) => i + 4);
    final keyPair = await Ed25519().newKeyPairFromSeed(signingSeed);
    final publicKey = (await keyPair.extractPublicKey()).bytes;
    final codec = KnowledgePackCodec();
    final repository = KnowledgeRepository(
      db: db,
      rootPath: directory.path,
      publicKey: publicKey,
      seedLoader: () async => codec.catalogFromSource(seed),
    );
    await repository.setFavorite('test', true);
    final update = await codec.export(
      source('2026.10.07', '新版'),
      signingSeed: signingSeed,
    );
    final result = await repository.importPack(update);
    expect(result.updated, 1);
    expect((await repository.load()).article('test')!.title, '新版');
    final previous = File(p.join(repository.activePath, 'manifest.json'));
    final manifest = await previous.readAsBytes();
    final corrupted = [...update];
    corrupted[update.length ~/ 2] ^= 0x80;
    await expectLater(repository.importPack(corrupted), throwsA(anything));
    expect((await previous.readAsBytes()), manifest);
    expect((await repository.load()).article('test')!.title, '新版');
    expect(await repository.favorites(), contains('test'));
  });
}
