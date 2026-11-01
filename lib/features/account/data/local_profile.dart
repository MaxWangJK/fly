import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../tasks/presentation/task_providers.dart';

class LocalProfile {
  const LocalProfile({this.name = '', this.avatar});
  final String name;
  final Uint8List? avatar;
}

final localProfileProvider = StreamProvider<LocalProfile>(
  (ref) => LocalProfileRepository(ref.watch(databaseProvider)).watch(),
);

/// Device-local preferences, outside the sync settings allowlist. Avatar bytes
/// must not accidentally become part of records-only cloud synchronization.
class LocalProfileRepository {
  LocalProfileRepository(this.db);
  final AppDatabase db;
  Stream<LocalProfile> watch() =>
      (db.select(
            db.appSettings,
          )..where((r) => r.key.isIn(const ['profile.name', 'profile.avatar'])))
          .watch()
          .map((rows) {
            final values = {for (final row in rows) row.key: row.value};
            Uint8List? avatar;
            try {
              if ((values['profile.avatar'] ?? '').isNotEmpty) {
                avatar = base64Decode(values['profile.avatar']!);
              }
            } on FormatException {
              avatar = null;
            }
            return LocalProfile(
              name: values['profile.name'] ?? '',
              avatar: avatar,
            );
          });
  Future<void> save(String name, Uint8List? avatar) async {
    if (name.trim().runes.length > 80) throw ArgumentError('Name is too long');
    if ((avatar?.length ?? 0) > 2 * 1024 * 1024) {
      throw ArgumentError('Avatar is too large');
    }
    await db.transaction(() async {
      for (final entry in {
        'profile.name': name.trim(),
        'profile.avatar': avatar == null ? '' : base64Encode(avatar),
      }.entries) {
        await db
            .into(db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: entry.key,
                value: entry.value,
                updatedAt: DateTime.now(),
              ),
            );
      }
    });
  }
}
