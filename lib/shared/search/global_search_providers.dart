import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/feature_flags.dart';

import '../../features/tasks/presentation/task_providers.dart';
import 'global_search_service.dart';
import '../../features/knowledge/presentation/knowledge_providers.dart';

final globalSearchServiceProvider = Provider<GlobalSearchService>(
  (ref) => GlobalSearchService(
    ref.watch(databaseProvider),
    knowledge: enableKnowledgeHub
        ? ref.watch(knowledgeRepositoryProvider)
        : null,
  ),
);
