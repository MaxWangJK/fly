import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tasks/presentation/task_providers.dart';
import 'global_search_service.dart';

final globalSearchServiceProvider = Provider<GlobalSearchService>(
  (ref) => GlobalSearchService(
    ref.watch(databaseProvider),
    // The book library deliberately has no content search.
    knowledge: null,
  ),
);
