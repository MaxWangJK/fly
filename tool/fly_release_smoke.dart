import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fly/app/settings/navigation_settings.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/storage/data_root_service.dart';
import 'package:fly/features/dashboard/data/dashboard_focus_repository.dart';
import 'package:fly/features/dashboard/domain/dashboard_focus.dart';
import 'package:fly/features/knowledge/data/knowledge_repository.dart';
import 'package:fly/main.dart' show FlyBootstrap;
import 'package:path/path.dart' as p;

/// Windows release smoke entry point. It uses only an explicitly supplied
/// isolated root, never the user's configured FlyData directory.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const smokeRoot = String.fromEnvironment('FLY_SMOKE_ROOT');
  if (smokeRoot.isEmpty) {
    throw StateError('Set FLY_SMOKE_ROOT to an isolated test directory.');
  }
  final support = Directory(p.join(smokeRoot, 'support'));
  final documents = Directory(p.join(smokeRoot, 'documents'));
  await support.create(recursive: true);
  await documents.create(recursive: true);
  final service = FlyDataRootService(
    supportDirectory: support,
    documentsDirectory: documents,
  );
  final dataRoot = p.join(smokeRoot, 'FlyData');
  await service.prepareFirstRun(
    dataRoot,
    useExistingDatabase: true,
    migrateLegacyDatabase: false,
  );
  final database = AppDatabase.atDataRoot(dataRoot);
  try {
    await database.ensureBuiltInData();
    final knowledge = await loadBundledKnowledge();
    if (knowledge.articles.length != 14) {
      throw StateError('Bundled Knowledge catalog is incomplete.');
    }
    final navigation = NavigationSettingsController(database);
    await navigation.ready;
    await navigation.update(const NavigationSettings(dashboardVisible: true));
    navigation.dispose();
    await DashboardFocusRepository(database).save(
      type: DashboardFocusType.mainMission,
      content: '1.0 release smoke test',
      day: DateTime.now(),
    );
  } finally {
    await database.close();
  }
  runApp(FlyBootstrap(dataRootService: service));
}
