import 'package:fly/core/database/app_database.dart';

/// Remove v18-only objects before reconstructing a genuine v1-v17 fixture.
Future<void> removeSyncSchema(AppDatabase db) async {
  final triggers = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'sync_%'",
      )
      .get();
  for (final trigger in triggers) {
    await db.customStatement('DROP TRIGGER "${trigger.read<String>('name')}"');
  }
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE 'sync_%' OR name LIKE 'lan_%')",
      )
      .get();
  for (final table in tables) {
    await db.customStatement('DROP TABLE "${table.read<String>('name')}"');
  }
}
