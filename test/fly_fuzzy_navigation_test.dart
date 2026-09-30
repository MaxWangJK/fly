import 'package:drift/native.dart';
import 'package:fly/app/app.dart';
import 'package:fly/app/settings/navigation_settings.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/domain/customer.dart';
import 'package:fly/features/customers/presentation/customer_providers.dart';
import 'package:fly/features/files/data/file_browser_query.dart';
import 'package:fly/features/notes/data/note_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/orders/domain/order.dart';
import 'package:fly/features/orders/presentation/order_providers.dart';
import 'package:fly/features/reviews/data/daily_review_repository.dart';
import 'package:fly/features/reviews/presentation/daily_review_page.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/l10n/fly_localizations.dart';
import 'package:fly/shared/design_system/app_theme.dart';
import 'package:fly/shared/search/fuzzy_match.dart';
import 'package:fly/shared/search/global_search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fuzzy matching tolerates small typos but not unrelated short terms',
    () {
      expect(FuzzyMatch.matches('Jcak', ['Jack']), isTrue);
      expect(FuzzyMatch.matches('jck', ['Jack']), isTrue);
      expect(
        FuzzyMatch.matches('Philippnes WPC', ['Philippines', 'WPC']),
        isTrue,
      );
      expect(FuzzyMatch.matches('报价', ['发送报价单']), isTrue);
      expect(FuzzyMatch.matches('Ja', ['Jack']), isTrue);
      expect(FuzzyMatch.matches('Jx', ['Jack']), isFalse);
      expect(FuzzyMatch.matches('unrelated', ['Jack']), isFalse);
    },
  );

  test('customer, order, notes, files and Ctrl+K share fuzzy search', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureBuiltInData();
    final customers = DriftCustomerRepository(db);
    final customer = await customers.createCustomer(name: 'Jack');
    final orders = DriftOrderRepository(db);
    final order = await orders.createOrder(
      customerId: customer.id,
      orderNumber: 'SO-2026-001',
    );
    final note = await NoteRepository(db).create('Negotiation guide');
    final now = DateTime.now();
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: 'file-1',
            ownerType: 'library',
            ownerId: 'library',
            fileName: 'wpc-price.pdf',
            originalName: 'WPC price.pdf',
            relativePath: 'files/wpc-price.pdf',
            fileSize: 10,
            createdAt: now,
            updatedAt: now,
          ),
        );
    expect(
      (await customers
              .watchCustomers(
                const CustomerQuery(
                  projection: CustomerProjection.all,
                  search: 'Jcak',
                ),
              )
              .first)
          .single
          .id,
      customer.id,
    );
    expect(
      (await orders
              .watchOrders(
                const OrderQuery(
                  projection: OrderProjection.all,
                  search: 'S0-2026-001',
                ),
              )
              .first)
          .single
          .id,
      order.id,
    );
    expect(
      (await NoteRepository(
        db,
      ).watch(recent: true, search: 'Negoitation').first).single.id,
      note,
    );
    expect(
      (await FileBrowserQuery(db)
              .watch(collection: FileCollection.recent, search: 'prcie')
              .first)
          .single
          .file
          .id,
      'file-1',
    );
    final global = GlobalSearchService(db);
    expect(
      (await global.search('Jcak')).any(
        (item) =>
            item.type == SearchResultType.customer &&
            item.entityId == customer.id,
      ),
      isTrue,
    );
    expect(
      (await global.search('prcie')).any(
        (item) =>
            item.type == SearchResultType.file && item.entityId == 'file-1',
      ),
      isTrue,
    );
  });

  testWidgets(
    'fresh navigation hides Dashboard and selects first customer/order',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final records = await tester.runAsync(() async {
        await db.ensureBuiltInData();
        final crm = DriftCustomerRepository(db);
        var customer = await crm.createCustomer(name: 'Auto select Jack');
        final today = DateTime.now();
        customer = customer.copyWith(
          nextFollowUpDate: DateTime(today.year, today.month, today.day),
        );
        await crm.saveCustomer(customer);
        final order = await DriftOrderRepository(db)
            .createOrder(customerId: customer.id, orderNumber: 'SO-AUTO-1');
        final task = await DriftTaskRepository(db).createTask(
          title: 'Prepare quotation',
          dueDate: DateTime(today.year, today.month, today.day),
        );
        return (customer.id, order.id, task.id);
      });
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const FlyApp()),
      );
      await _settle(tester);
      expect(
        container.read(navigationSettingsProvider).value.dashboardVisible,
        false,
      );
      expect(find.byKey(const ValueKey('primary-dashboard')), findsNothing);
      expect(container.read(selectedCustomerIdProvider), records!.$1);
      await tester.tap(find.byKey(const ValueKey('primary-orders')));
      await _settle(tester);
      expect(container.read(selectedOrderIdProvider), records.$2);
      await tester.tap(find.byKey(const ValueKey('primary-tasks')));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('task-search')),
        'quotoation',
      );
      await _settle(tester);
      expect(find.text('Prepare quotation'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('task-search')),
        'unrelated',
      );
      await _settle(tester);
      expect(find.text('Prepare quotation'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
  );

  testWidgets('review falls back to calendar yesterday without older records', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureBuiltInData();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localTodayProvider.overrideWith((ref) => DateTime(2026, 9, 26)),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FlyTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: const [FlyLocalizationsDelegate()],
          home: const Scaffold(body: DailyReviewPage()),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('Previous day'));
    await _settle(tester);
    expect(find.text('2026-09-25'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets('review previous button skips empty days to latest record', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureBuiltInData();
    await DailyReviewRepository(db).saveAnswer('2026-09-24', 'q1', 'Recorded');
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localTodayProvider.overrideWith((ref) => DateTime(2026, 9, 26)),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FlyTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: const [FlyLocalizationsDelegate()],
          home: const Scaffold(body: DailyReviewPage()),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('Previous day'));
    await _settle(tester);
    expect(find.text('2026-09-24'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}
