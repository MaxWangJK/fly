import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/customers/presentation/customer_list_page.dart';
import 'package:fly/features/customers/presentation/customer_providers.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/data/financial_attachment_service.dart';
import 'package:fly/features/orders/data/order_file_service.dart';
import 'package:fly/features/orders/domain/financial_attachment_ids.dart';
import 'package:fly/features/orders/domain/order.dart';
import 'package:fly/features/orders/presentation/order_detail_panel.dart';
import 'package:fly/features/orders/presentation/order_providers.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'input_continuity_widget_test.dart' as ui;

void main() {
  test('attachment references read legacy IDs and serialize multiple IDs', () {
    expect(FinancialAttachmentIds.decode(null), isEmpty);
    expect(FinancialAttachmentIds.decode('legacy'), ['legacy']);
    expect(FinancialAttachmentIds.encode(['legacy']), 'legacy');
    expect(
      FinancialAttachmentIds.decode(
        FinancialAttachmentIds.encode(['a', 'b', 'a']),
      ),
      ['a', 'b'],
    );
    expect(FinancialAttachmentIds.encode([]), isNull);
  });

  test('multiple financial attachment IDs survive database restart and sync serialization', () async {
    final root = await Directory.systemTemp.createTemp('fly-finance-reopen-');
    final databaseFile = File('${root.path}/test.db');
    var db = AppDatabase(NativeDatabase(databaseFile));
    try {
      await db.ensureBuiltInData();
      await SyncOutboxRepository(db).bind('test-finance-workspace');
      final repo = DriftOrderRepository(db);
      final customer = await DriftCustomerRepository(db)
          .createCustomer(name: 'Durable test');
      final order = await repo.createOrder(
        customerId: customer.id,
        orderNumber: 'DURABLE-PI',
      );
      final encoded = FinancialAttachmentIds.encode(['receipt-a', 'receipt-b']);
      await repo.addPayment(
        order.id,
        amount: 123,
        currency: 'USD',
        paymentType: 'Free note',
        paidAt: DateTime.now(),
        attachmentId: encoded,
      );
      await repo.addCostEntry(
        order.id,
        amountMinor: 456,
        currency: 'CNY',
        costType: '',
        occurredAt: DateTime.now(),
        attachmentId: encoded,
      );
      await db.close();
      db = AppDatabase(NativeDatabase(databaseFile));
      final reopened = DriftOrderRepository(db);
      expect(
        (await reopened.watchPayments(order.id).first).single.attachmentIds,
        ['receipt-a', 'receipt-b'],
      );
      expect(
        (await reopened.watchCostEntries(order.id).first).single.attachmentIds,
        ['receipt-a', 'receipt-b'],
      );
      final outgoing = await SyncOutboxRepository(db).prepare(limit: 1000);
      for (final entity in ['order_payments', 'order_cost_entries']) {
        final row = outgoing.singleWhere((m) => m['entityType'] == entity);
        expect((row['payload'] as Map)['attachment_id'], encoded);
      }
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });

  test('failed import/save rolls back new files, preserving old attachments and entry', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('fly-finance-failure-');
    try {
      await db.ensureBuiltInData();
      final repo = DriftOrderRepository(db);
      final customer = await DriftCustomerRepository(db)
          .createCustomer(name: 'Test');
      final order = await repo.createOrder(
        customerId: customer.id,
        orderNumber: 'TEST',
      );
      final original = await File('${root.path}/original.txt')
          .writeAsString('original');
      final source = await File('${root.path}/new.txt').writeAsString('new');
      final storage = LocalOrderFileStorage(dataRootPath: '${root.path}/data');
      final service = FinancialAttachmentService(repo, storage);
      final payment = await repo.addPayment(
        order.id,
        amount: 100,
        currency: 'USD',
        paymentType: '',
        paidAt: DateTime.now(),
      );
      await service.save(
        orderId: order.id,
        documentType: OrderDocumentType.payment,
        retainedIds: [],
        sourcePaths: [original.path],
        persist: (ids) => repo.savePayment(payment.copyWith(attachmentId: ids)),
      );
      final before = (await repo.watchFiles(order.id).first).single;
      for (final missing in [true, false]) {
        await expectLater(
          service.save(
            orderId: order.id,
            documentType: OrderDocumentType.payment,
            retainedIds: [before.id],
            sourcePaths: [source.path, if (missing) '${root.path}/missing.txt'],
            persist: (_) async => throw StateError('synthetic save failure'),
          ),
          throwsA(anything),
        );
        expect((await repo.watchFiles(order.id).first).map((f) => f.id), [
          before.id,
        ]);
        expect(
          (await repo.watchPayments(order.id).first).single.attachmentIds,
          [before.id],
        );
        expect(
          await File(await storage.absolutePath(before.localRelativePath))
              .readAsString(),
          'original',
        );
        expect(
          await Directory('${root.path}/data')
              .list(recursive: true)
              .where((f) => f is File)
              .length,
          1,
        );
      }
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });

  for (final phone in [false, true]) {
    testWidgets(
      'creating a B customer keeps category route and filter on phone=$phone',
      (tester) async {
        ui.viewport(tester, phone);
        final db = AppDatabase(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        final repo = DriftCustomerRepository(db);
        final category = (await tester.runAsync(() async {
          await db.ensureBuiltInData();
          return (await repo.watchCategories().first).firstWhere(
            (c) => c.name == 'B级',
          );
        }))!;
        container.read(customerTagFilterProvider.notifier).state = {
          category.tagId!,
        };
        final path = '/customers/category/${category.id}';
        final router = GoRouter(
          initialLocation: path,
          routes: [
            GoRoute(
              path: path,
              builder: (_, _) => Scaffold(
                body: CustomerListPage(
                  projection: CustomerProjection.category,
                  categoryId: category.id,
                ),
              ),
            ),
            GoRoute(
              path: '/customers/all',
              builder: (_, _) => const Scaffold(body: Text('wrong route')),
            ),
          ],
        );
        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp.router(
                routerConfig: router,
                locale: const Locale('zh'),
                supportedLocales: FlyLocalizations.supportedLocales,
                localizationsDelegates: const [
                  FlyLocalizationsDelegate(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: FlyTheme.light(),
              ),
            ),
          );
          await ui.settle(tester);
          await tester.tap(find.byKey(const ValueKey('customer-add-button')));
          await ui.settle(tester);
          await tester.enterText(
            find.byKey(const ValueKey('customer-quick-add-input')),
            'New B customer',
          );
          await tester.enterText(
            find.byKey(const ValueKey('customer-create-country')),
            'Canada',
          );
          final status = (await tester.runAsync(
            () => repo.watchStatuses().first,
          ))!.first;
          await ui.reveal(
            tester,
            find.byKey(ValueKey('customer-create-status-${status.id}')),
          );
          await tester.tap(
            find.byKey(ValueKey('customer-create-status-${status.id}')),
          );
          await tester.tap(find.byKey(const ValueKey('phone-create-customer')));
          await ui.settle(tester);
          expect(find.byType(AlertDialog), findsNothing);
          expect(router.routeInformationProvider.value.uri.path, path);
          expect(container.read(customerTagFilterProvider), {category.tagId!});
          final created = (await tester.runAsync(
            () => repo
                .watchCustomers(
                  const CustomerQuery(projection: CustomerProjection.all),
                )
                .first,
          ))!.single;
          expect(created.categoryId, category.id);
          expect(find.text('New B customer'), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
          container.dispose();
          await ui.settle(tester);
          await tester.runAsync(db.close);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    for (final cost in [false, true]) {
      testWidgets(
        'financial attachment edit, cancel, multiple files, removal, reopen phone=$phone cost=$cost',
        (tester) async {
          ui.viewport(tester, phone);
          if (!phone) tester.view.physicalSize = const Size(1264, 681);
          final db = AppDatabase(NativeDatabase.memory());
          final root = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('fly-finance-ui-'),
          ))!;
          final repo = DriftOrderRepository(db);
          final storage = LocalOrderFileStorage(
            dataRootPath: '${root.path}/data',
          );
          final setup = (await tester.runAsync(() async {
            await ui.fonts();
            await db.ensureBuiltInData();
            final customer = await DriftCustomerRepository(db)
                .createCustomer(name: 'Attachment test');
            final order = await repo.createOrder(
              customerId: customer.id,
              orderNumber: 'ATTACHMENT-PI',
            );
            final source = await File('${root.path}/receipt.png').writeAsBytes(
              base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAIAAADYYG7QAAAAS0lEQVR4nO3OMQHAIADAMMDvFGAFsfv39GRHoiDzOXv8ybod+BIqQkWoCBWhIlSEilARKkJFqAgVoSJUhIpQESpCRagIFaEiVITKC2iMAeTHNQDfAAAAAElFTkSuQmCC',
              ),
            );
            final stored = await storage.importFile(
              sourcePath: source.path,
              orderId: order.id,
              documentType: OrderDocumentType.payment,
            );
            final file = await repo.addFileMetadata(
              orderId: order.id,
              fileName: stored.fileName,
              originalName: stored.originalName,
              documentType: OrderDocumentType.payment,
              localRelativePath: stored.relativePath,
              fileSize: stored.fileSize,
              mimeType: stored.mimeType,
            );
            final id = cost
                ? (await repo.addCostEntry(
                    order.id,
                    amountMinor: 1000,
                    currency: 'CNY',
                    costType: '工厂成本',
                    occurredAt: DateTime.now(),
                    attachmentId: file.id,
                  )).id
                : (await repo.addPayment(
                    order.id,
                    amount: 1000,
                    currency: 'USD',
                    paymentType: '定金',
                    paidAt: DateTime.now(),
                    attachmentId: file.id,
                  )).id;
            final more = await File('${root.path}/invoice.pdf')
                .writeAsString('synthetic test document');
            return (
              order: order,
              file: file,
              id: id,
              paths: [source.path, more.path],
            );
          }))!;
          final container = ProviderContainer(
            overrides: [
              databaseProvider.overrideWithValue(db),
              orderFileStorageProvider.overrideWithValue(storage),
            ],
          );
          final capture = GlobalKey();
          final row = find.byKey(
            ValueKey('financial-${cost ? 'cost' : 'payment'}-${setup.id}'),
          );
          Future<void> open() async {
            await ui.reveal(tester, row);
            await tester.tap(
              find.descendant(
                of: row,
                matching: find.byType(PopupMenuButton<String>),
              ),
            );
            await ui.settle(tester);
            await tester.tap(find.text('编辑').last);
            await ui.settle(tester);
          }

          Future<List<String>> savedIds() async => (await tester.runAsync(
            () async => cost
                ? (await repo.watchCostEntries(setup.order.id).first)
                      .single
                      .attachmentIds
                : (await repo.watchPayments(setup.order.id).first)
                      .single
                      .attachmentIds,
          ))!;
          try {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: RepaintBoundary(
                  key: capture,
                  child: ui.app(
                    OrderExtensionPanel(
                      orderId: setup.order.id,
                      type: OrderExtensionType.financial,
                      onClose: () {},
                    ),
                    phone: phone,
                  ),
                ),
              ),
            );
            await ui.settle(tester);
            await open();
            expect(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text('备注'),
              ),
              findsOneWidget,
            );
            expect(
              find.byKey(ValueKey('financial-retained-${setup.file.id}')),
              findsOneWidget,
            );
            await ui.reveal(tester, find.byTooltip('移除附件'));
            await tester.tap(find.byTooltip('移除附件'));
            await tester.tap(find.widgetWithText(TextButton, '取消'));
            await ui.settle(tester);
            expect(await savedIds(), [setup.file.id]);
            await open();
            await tester.enterText(
              find.byKey(const ValueKey('financial-entry-type')),
              '',
            );
            if (phone) {
              const channel = MethodChannel('plugins.flutter.io/file_selector');
              var selectedMultiple = false;
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                channel,
                (call) async {
                  selectedMultiple =
                      (call.arguments as Map)['multiple'] == true;
                  return setup.paths;
                },
              );
              try {
                await ui.reveal(
                  tester,
                  find.byKey(const ValueKey('financial-entry-attachment')),
                );
                await tester.tap(
                  find.byKey(const ValueKey('financial-entry-attachment')),
                );
                await ui.settle(tester);
                expect(selectedMultiple, isTrue);
              } finally {
                tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                  channel,
                  null,
                );
              }
            } else {
              final target = tester.widget<DropTarget>(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(DropTarget),
                ),
              );
              target.onDragDone!(
                DropDoneDetails(
                  files: setup.paths.map(DropItemFile.new).toList(),
                  localPosition: Offset.zero,
                  globalPosition: Offset.zero,
                ),
              );
            }
            await ui.settle(tester);
            expect(find.text('共 3 个附件'), findsOneWidget);
            await ui.reveal(
              tester,
              find.byKey(ValueKey('financial-retained-${setup.file.id}')),
            );
            await tester.tap(
              find.descendant(
                of: find.byKey(ValueKey('financial-retained-${setup.file.id}')),
                matching: find.byTooltip('移除附件'),
              ),
            );
            await ui.settle(tester);
            expect(find.text('共 2 个附件'), findsOneWidget);
            if (const bool.fromEnvironment('FLY_FINANCE_CAPTURE')) {
              await ui.capture(
                tester,
                capture,
                'financial-${phone ? 'phone' : 'desktop'}-${cost ? 'cost' : 'payment'}',
              );
            }
            await tester.runAsync(() async {
              await tester.tap(find.widgetWithText(FilledButton, '保存'));
              await Future<void>.delayed(const Duration(milliseconds: 300));
            });
            await ui.settle(tester);
            expect(
              find.byType(AlertDialog),
              findsNothing,
              reason: find
                  .descendant(
                    of: find.byType(AlertDialog),
                    matching: find.byType(Text),
                  )
                  .evaluate()
                  .map((e) => (e.widget as Text).data)
                  .join(' | '),
            );
            final ids = await savedIds();
            expect(ids, hasLength(2));
            expect(ids, isNot(contains(setup.file.id)));
            await open();
            for (final id in ids) {
              expect(
                find.byKey(ValueKey('financial-retained-$id')),
                findsOneWidget,
              );
            }
            final old = find.byKey(ValueKey('financial-retained-${ids.first}'));
            await ui.reveal(tester, old);
            await tester.tap(
              find.descendant(of: old, matching: find.byTooltip('移除附件')),
            );
            await tester.runAsync(() async {
              await tester.tap(find.widgetWithText(FilledButton, '保存'));
              await Future<void>.delayed(const Duration(milliseconds: 300));
            });
            await ui.settle(tester);
            expect(await savedIds(), [ids.last]);
            await open();
            final last = find.byKey(ValueKey('financial-retained-${ids.last}'));
            await ui.reveal(tester, last);
            await tester.tap(
              find.descendant(of: last, matching: find.byTooltip('移除附件')),
            );
            await tester.runAsync(() async {
              await tester.tap(find.widgetWithText(FilledButton, '保存'));
              await Future<void>.delayed(const Duration(milliseconds: 300));
            });
            await ui.settle(tester);
            expect(await savedIds(), isEmpty);
            expect(
              (await tester.runAsync(
                () => repo.watchFiles(setup.order.id).first,
              ))!,
              hasLength(3),
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            container.dispose();
            await ui.settle(tester);
            await tester.runAsync(() async {
              await db.close();
              await root.delete(recursive: true);
            });
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }
}
