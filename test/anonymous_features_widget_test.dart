import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/startup_services_runtime.dart';
import 'package:fly/core/analytics/analytics_action.dart';
import 'package:fly/core/analytics/analytics_service.dart';
import 'package:fly/core/analytics/analytics_storage.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/core/updates/update_controller.dart';
import 'package:fly/core/updates/update_service.dart';
import 'package:fly/core/updates/update_widgets.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/customers/import/customer_import_dialog.dart';
import 'package:fly/features/customers/import/customer_import_providers.dart';
import 'package:fly/features/customers/import/customer_import_service.dart';
import 'package:fly/features/customers/import/customer_template_export.dart';
import 'package:fly/features/customers/presentation/customer_create_dialog.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';

import 'input_continuity_widget_test.dart' as ui;

class _Source extends UpdateService {
  _Source(this.result);
  final UpdateCheck result;
  @override
  Future<UpdateCheck> check() async => result;
}

class _MemoryAnalytics implements AnalyticsStorage {
  var state = const AnalyticsState(deviceCode: 'ANONYMOUS2345678');
  @override
  Future<AnalyticsState> loadOrCreate(String Function() generateCode) async =>
      state;
  @override
  Future<void> markInstallReported(String code) async =>
      state = state.copyWith(installReported: true);
  @override
  Future<void> markDailyOpenReported(String code, String day) async =>
      state = state.copyWith(lastOpenDate: day);
}

class _HangingTransport implements AnalyticsTransport {
  final install = Completer<bool>();
  final actions = <int>[];
  @override
  Future<bool> send(String code, AnalyticsAction action) {
    actions.add(action.code);
    return action == AnalyticsAction.install
        ? install.future
        : Future.value(false);
  }
}

class _Exporter extends CustomerTemplateExporter {
  final saved = <Uint8List>[];
  @override
  Future<TemplateExportResult> save(
    Uint8List bytes, {
    required Rect shareOrigin,
  }) async {
    saved.add(bytes);
    expect(shareOrigin.width, greaterThan(0));
    return TemplateExportResult.saved;
  }
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30; i++) {
    await ui.settle(tester);
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

void main() {
  testWidgets(
    'analytics does not block app startup or show errors on failure',
    (tester) async {
      ui.viewport(tester, false);
      final transport = _HangingTransport();
      final analytics = AnalyticsService(
        storage: _MemoryAnalytics(),
        transport: transport,
      );
      final controller = UpdateController(
        service: _Source(const UpdateCheck()),
        launchDownload: (_) async => true,
      );
      final container = ProviderContainer(
        overrides: [updateControllerProvider.overrideWith((ref) => controller)],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: ui.app(
              StartupServicesRuntime(
                analyticsFactory: () async => analytics,
                child: const Center(child: Text('Workspace ready')),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Workspace ready'), findsOneWidget);
        expect(transport.actions, [1]);
        expect(transport.install.isCompleted, isFalse);
        expect(find.byType(AlertDialog), findsNothing);
        transport.install.complete(false);
        await ui.settle(tester);
        expect(transport.actions, [1, 2]);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(MaterialBanner), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!transport.install.isCompleted) transport.install.complete(false);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final size in [
    const Size(1200, 850),
    const Size(390, 844),
    const Size(844, 390),
    const Size(320, 720),
  ]) {
    testWidgets(
      'update notice is dismissible and downloads only on click at $size',
      (tester) async {
        final phone = size.width < 1000;
        ui.viewport(tester, phone);
        tester.view.physicalSize = size;
        await tester.runAsync(ui.fonts);
        final release = AppRelease(
          version: FlyVersion.parse('3.0.0+88'),
          downloadUri: Uri.parse(
            'https://example.test/api/updates/download/Fly-3.0.exe',
          ),
          fileName: 'Fly-3.0.exe',
          size: 100,
          sha256: List.filled(64, 'a').join(),
        );
        final downloads = <Uri>[];
        final controller = UpdateController(
          service: _Source(UpdateCheck(latest: release, isNewer: true)),
          launchDownload: (uri) async {
            downloads.add(uri);
            return true;
          },
        );
        final container = ProviderContainer(
          overrides: [
            updateControllerProvider.overrideWith((ref) => controller),
          ],
        );
        final capture = GlobalKey();
        try {
          await controller.check(silent: true);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: capture,
                child: ui.app(
                  const AppUpdateNotice(
                    child: Center(child: Text('Workspace ready')),
                  ),
                  phone: phone,
                ),
              ),
            ),
          );
          await ui.settle(tester);
          expect(find.textContaining('发现新版本'), findsOneWidget);
          expect(downloads, isEmpty);
          await ui.capture(
            tester,
            capture,
            'anonymous-update-${size.width.toInt()}',
          );
          await tester.tap(find.text('下载更新'));
          await ui.settle(tester);
          expect(downloads, [release.downloadUri]);
          await tester.tap(find.text('稍后'));
          await ui.settle(tester);
          expect(find.textContaining('发现新版本'), findsNothing);
          expect(find.text('Workspace ready'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'customer creation keeps import on desktop and hides it on mobile at $size',
      (tester) async {
        final phone = size.width < 1000;
        ui.viewport(tester, phone);
        tester.view.physicalSize = size;
        final db = AppDatabase(NativeDatabase.memory());
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('fly-import-widget-'),
        ))!;
        final exporter = _Exporter();
        var filePicks = 0;
        late File workbook;
        await tester.runAsync(() async {
          await db.ensureBuiltInData();
          await ui.fonts();
          final book = Excel.decodeBytes(
            CustomerImportService(db).buildTemplate(),
          );
          book['Customers'].appendRow(
            [
              'Alex Import',
              'Australia',
              'A',
              '新客户',
              'Exhibition',
              'Example Trade',
              'alex@example.test',
            ].map(TextCellValue.new).toList(),
          );
          workbook = await File('${directory.path}/customers.xlsx')
              .writeAsBytes(book.encode()!);
        });
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            customerTemplateExporterProvider.overrideWithValue(exporter),
            customerImportFilePickerProvider.overrideWithValue(() async {
              filePicks++;
              return XFile(workbook.path);
            }),
          ],
        );
        final capture = GlobalKey();
        Customer? selected;
        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: capture,
                child: ui.app(
                  Builder(
                    builder: (context) => Center(
                      child: TextButton(
                        onPressed: () async {
                          selected = await showDialog<Customer>(
                            context: context,
                            builder: (_) => const CustomerCreateDialog(),
                          );
                        },
                        child: const Text('Add customer'),
                      ),
                    ),
                  ),
                  phone: phone,
                ),
              ),
            ),
          );
          await tester.tap(find.text('Add customer'));
          await ui.settle(tester);
          await tester.enterText(
            find.byKey(const ValueKey('customer-quick-add-input')),
            'Unsaved draft',
          );
          await ui.settle(tester);
          if (phone) {
            expect(
              find.byKey(const ValueKey('customer-batch-import')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('customer-import-template')),
              findsNothing,
            );
            final country = find.byKey(
              const ValueKey('customer-create-country'),
            );
            await ui.reveal(tester, country);
            await tester.enterText(country, 'Australia');
            for (final key in [
              'customer-create-category-category-a',
              'customer-create-status-customer-new',
            ]) {
              final choice = find.byKey(ValueKey(key));
              await ui.reveal(tester, choice);
              await tester.tap(choice);
            }
            await ui.settle(tester);
            await ui.capture(
              tester,
              capture,
              'mobile-create-no-import-${size.width.toInt()}',
            );
            await tester.tap(
              find.byKey(const ValueKey('phone-create-customer')),
            );
            await ui.settle(tester);
            expect(find.byType(CustomerCreateDialog), findsNothing);
            expect(selected?.name, 'Unsaved draft');
            expect(exporter.saved, isEmpty);
            expect(filePicks, 0);
            expect(tester.takeException(), isNull);
            return;
          }
          final template = find.byKey(
            const ValueKey('customer-import-template'),
          );
          await tester.ensureVisible(template);
          await ui.settle(tester);
          await ui.capture(
            tester,
            capture,
            'anonymous-create-${size.width.toInt()}',
          );
          await tester.tap(template);
          await ui.settle(tester);
          expect(exporter.saved, hasLength(1));
          expect(
            Excel.decodeBytes(exporter.saved.single)
                .tables['Customers']!
                .maxColumns,
            11,
          );
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(const ValueKey('customer-quick-add-input')),
                )
                .controller!
                .text,
            'Unsaved draft',
          );
          expect(
            (await tester.runAsync(() => db.select(db.customers).get()))!,
            isEmpty,
          );
          final batch = find.byKey(const ValueKey('customer-batch-import'));
          await tester.ensureVisible(batch);
          await tester.tap(batch);
          await ui.settle(tester);
          expect(find.byType(CustomerImportDialog), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('choose-customer-import-file')),
          );
          await _waitFor(
            tester,
            find.byKey(const ValueKey('confirm-customer-import')),
          );
          expect(find.text('Alex Import'), findsOneWidget);
          await ui.capture(
            tester,
            capture,
            'anonymous-import-${size.width.toInt()}',
          );
          await tester.tap(
            find.byKey(const ValueKey('confirm-customer-import')),
          );
          await _waitFor(tester, find.text('导入完成'));
          await tester.tap(find.text('完成').last);
          await ui.settle(tester);
          expect(find.byType(CustomerCreateDialog), findsNothing);
          expect(selected?.name, 'Alex Import');
          final records = (await tester.runAsync(
            () => db.select(db.customers).get(),
          ))!;
          expect(records, hasLength(1));
          expect(records.single.name, 'Alex Import');
          expect(records.single.categoryId, 'category-a');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          await ui.settle(tester);
          await tester.runAsync(() async {
            await db.close();
            await directory.delete(recursive: true);
          });
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
