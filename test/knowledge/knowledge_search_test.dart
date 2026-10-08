import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/knowledge/data/knowledge_repository.dart';
import 'package:fly/shared/search/global_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Ctrl+K service groups official articles separately from personal records',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final knowledge = KnowledgeRepository(
        db: database,
        rootPath: null,
        publicKey: const [],
        seedLoader: loadBundledKnowledge,
      );
      final results = await GlobalSearchService(
        database,
        knowledge: knowledge,
      ).search('报价', perGroup: 8);
      expect(
        results.where((r) => r.type == SearchResultType.knowledge),
        isNotEmpty,
      );
      expect(
        results
            .where((r) => r.type == SearchResultType.knowledge)
            .any((r) => r.title.contains('报价')),
        isTrue,
      );
    },
  );
}
