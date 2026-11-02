import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';
import 'package:fly/features/sync/presentation/sync_controller.dart';
import 'package:fly/features/sync/presentation/sync_status_details.dart';
import 'package:fly/features/sync/services/file_sync_service.dart';
import 'package:fly/features/sync/services/sync_engine.dart';
import 'package:fly/l10n/fly_localizations.dart';

class _UnusedTransport implements SyncTransport {
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
  }) => throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> uploadChunk(String path, List<int> chunk) =>
      throw UnimplementedError();
  @override
  Future<void> download(String path, String destination) =>
      throw UnimplementedError();
  @override
  void close() {}
}

void main() {
  testWidgets(
    'connected status still reports missing files and displays transfer progress',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-status-test-'),
      ))!;
      final outbox = SyncOutboxRepository(db);
      await tester.runAsync(() async {
        await db.ensureBuiltInData();
        await db.customStatement('DELETE FROM sync_outbox');
        await ManagedFileRepository(db).commit(
          ImportedFile(
            id: 'missing',
            relativePath: 'files/missing.jpg',
            name: 'missing.jpg',
            size: 1024,
            sha256: 'a'.padRight(64, '0'),
          ),
        );
      });
      final files = FileSyncService(db, root.path, _UnusedTransport())
        ..total = 3
        ..completed = 1
        ..phase = 'downloading'
        ..currentFile = 'missing.jpg'
        ..bytesTransferred = 512
        ..bytesTotal = 1024;
      final engine =
          SyncEngine(
              outbox: outbox,
              transport: files.transport,
              cursorKey: 'lanCursor',
              files: files,
            )
            ..enabled = true
            ..running = true
            ..lastSuccess = DateTime(2026, 10, 14, 12, 30)
            ..status = '正在同步';
      final controller = SyncController(outbox, root.path)
        ..ready = true
        ..connectionMode = SyncConnectionMode.lan
        ..engine = engine;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              syncControllerProvider.overrideWith((ref) => controller),
            ],
            child: MaterialApp(
              locale: const Locale('zh'),
              supportedLocales: FlyLocalizations.supportedLocales,
              localizationsDelegates: const [
                FlyLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Scaffold(
                body: SingleChildScrollView(child: SyncStatusDetails()),
              ),
            ),
          ),
        );
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(controller.connected, isTrue);
        expect(find.textContaining('文件是否已到本机'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('sync-pending-downloads')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('sync-pending-changes')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byKey(const ValueKey('sync-file-progress')),
              )
              .value,
          .5,
        );
        expect(find.textContaining('2026-10-14 12:30:00'), findsOneWidget);
        expect(find.textContaining('文件检查'), findsNothing);
        // Checks may still run internally, but never display filenames or
        // progress until bytes are actually transferred.
        files.phase = 'checking';
        controller.notifyListeners();
        await tester.pump();
        expect(find.text('missing.jpg'), findsNothing);
        expect(find.byKey(const ValueKey('sync-file-progress')), findsNothing);
        expect(
          find.byKey(const ValueKey('sync-pending-downloads')),
          findsOneWidget,
        );
        for (final phase in ['uploading', 'downloading']) {
          files.phase = phase;
          controller.notifyListeners();
          await tester.pump();
          expect(find.text('missing.jpg'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('sync-file-progress')),
            findsOneWidget,
          );
        }
        files.phase = 'idle';
        controller.notifyListeners();
        await tester.pump();
        expect(find.byKey(const ValueKey('sync-file-progress')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        engine.running = false;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await db.close();
          await root.delete(recursive: true);
        });
      }
    },
  );
}
