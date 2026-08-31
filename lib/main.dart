import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';
import 'features/tasks/data/drift_task_repository.dart';
import 'features/tasks/domain/task_repository.dart';
import 'features/tasks/presentation/task_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  await database.ensureBuiltInData();
  final repository = DriftTaskRepository(database);
  if (kDebugMode) {
    await repository.seedDevelopmentData();
  }

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        taskRepositoryProvider.overrideWithValue(repository as TaskRepository),
      ],
      child: const FlyApp(),
    ),
  );
}
