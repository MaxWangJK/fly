import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/data_root_providers.dart';
import '../../tasks/presentation/task_providers.dart';
import '../data/knowledge_repository.dart';
import '../domain/knowledge_models.dart';

// The corresponding signing seed is generated locally and is never checked in.
// A publisher can replace this key at build time when rotating credentials.
const knowledgePackPublicKey = String.fromEnvironment(
  'KNOWLEDGE_PUBLIC_KEY',
  defaultValue: 'IeJPConD0acjgqybkPvX0Q2rN8l2FaAlzhmODYnqAV0=',
);

final knowledgeRepositoryProvider = Provider<KnowledgeRepository>((ref) {
  List<int> key;
  try {
    key = base64Url.decode(base64Url.normalize(knowledgePackPublicKey));
  } on FormatException {
    key = const [];
  }
  return KnowledgeRepository(
    db: ref.watch(databaseProvider),
    rootPath: ref.watch(dataRootPathProvider),
    seedLoader: loadBundledKnowledge,
    publicKey: key,
  );
});

final knowledgeCatalogProvider = FutureProvider<KnowledgeCatalog>(
  (ref) => ref.watch(knowledgeRepositoryProvider).load(),
);

final knowledgeFavoritesProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(knowledgeRepositoryProvider).favorites(),
);
