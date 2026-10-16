import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../../../core/storage/data_root_providers.dart';
import '../../tasks/presentation/task_providers.dart';
import '../data/fly_book_repository.dart';
import '../domain/fly_book.dart';
import 'knowledge_providers.dart';
import 'knowledge_html_viewer.dart';

typedef FlyBookPageBuilder = Widget Function(
  String html,
  ValueChanged<double> onProgress,
  ValueChanged<String> onLink,
  Key key,
);
final flyBookPageBuilderProvider = Provider<FlyBookPageBuilder>(
  (ref) =>
      (html, onProgress, onLink, key) => KnowledgeHtmlViewer(
        key: key,
        html: html,
        onProgress: onProgress,
        onLink: onLink,
        onImage: (_) {},
      ),
);

const flyBookContentKey = String.fromEnvironment('FLY_BOOK_CONTENT_KEY');

List<int> _decodeKey(String text) {
  try {
    return base64Url.decode(base64Url.normalize(text));
  } on FormatException {
    return const [];
  }
}

final flyBookLibraryProvider = Provider<FlyBookLibrary>(
  (ref) => FlyBookLibrary(
    rootPath: ref.watch(dataRootPathProvider),
    contentKey: _decodeKey(flyBookContentKey),
    publicKey: _decodeKey(knowledgePackPublicKey),
  ),
);
final flyBooksProvider = FutureProvider<List<FlyBook>>(
  (ref) => ref.watch(flyBookLibraryProvider).load(),
);
final flyReadingRepositoryProvider = Provider<FlyReadingRepository>(
  (ref) => FlyReadingRepository(ref.watch(databaseProvider)),
);
final flyReadingStateProvider = FutureProvider<FlyReadingState>(
  (ref) => ref.watch(flyReadingRepositoryProvider).load(),
);
