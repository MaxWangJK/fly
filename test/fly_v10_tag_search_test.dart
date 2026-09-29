import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/notes/data/note_repository.dart';
import 'package:fly/features/notes/data/note_tag_repository.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/orders/data/drift_order_repository.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:fly/shared/search/global_search_service.dart';
import 'package:fly/shared/search/global_search_palette.dart';
import 'package:fly/l10n/fly_localizations.dart';

void main() {
  test(
    'tag counts aggregate independent definitions and filter exact links',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await db.ensureBuiltInData();
        final notes = NoteRepository(db);
        final id = await notes.create('Product guide');
        final unrelated = await notes.create('WPC is only a title');
        final tag = await NoteTagRepository(db).add(id, 'WPC');
        final customer = await DriftCustomerRepository(db)
            .createCustomer(name: 'Jack');
        await db
            .into(db.customerTagLinks)
            .insert(
              CustomerTagLinksCompanion.insert(
                customerId: customer.id,
                tagId: tag,
              ),
            );
        final now = DateTime.now();
        final order = await DriftOrderRepository(db)
            .createOrder(customerId: customer.id, orderNumber: 'SO-TAG');
        await db
            .into(db.orderTagLinks)
            .insert(
              OrderTagLinksCompanion.insert(orderId: order.id, tagId: tag),
            );
        await db
            .into(db.fileTags)
            .insert(
              FileTagsCompanion.insert(
                id: 'file-tag',
                name: 'wpc',
                normalizedName: 'wpc',
              ),
            );
        await db
            .into(db.attachments)
            .insert(
              AttachmentsCompanion.insert(
                id: 'file',
                ownerType: 'library',
                ownerId: '',
                fileName: 'guide.pdf',
                originalName: 'guide.pdf',
                relativePath: 'test/guide.pdf',
                fileSize: 10,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db
            .into(db.fileTagLinks)
            .insert(
              FileTagLinksCompanion.insert(fileId: 'file', tagId: 'file-tag'),
            );
        final search = GlobalSearchService(db);
        final aggregates = (await search.search('wpc'))
            .where((r) => r.type == SearchResultType.tag)
            .toList();
        expect(aggregates, hasLength(4));
        expect(
          Map.fromEntries([
            for (final tag in aggregates) ...tag.tagCounts.entries,
          ]),
          {
            SearchResultType.customer: 1,
            SearchResultType.order: 1,
            SearchResultType.workspaceNote: 1,
            SearchResultType.file: 1,
          },
        );
        expect(
          (await search.searchTag(' WPC ')).map((r) => r.entityId),
          unorderedEquals([id, customer.id, order.id, 'file']),
        );
        expect(
          (await search.searchTag('WPC')).any((r) => r.entityId == unrelated),
          false,
        );
        await notes.remove(id);
        await (db.update(db.attachments)..where((r) => r.id.equals('file')))
            .write(AttachmentsCompanion(deletedAt: Value(now)));
        expect(
          (await search.searchTag('WPC')).map((r) => r.entityId),
          unorderedEquals([customer.id, order.id]),
        );
        expect(await search.searchTag('WP'), isEmpty);
      } finally {
        await db.close();
      }
    },
  );

  testWidgets('palette opens exact tag results and clears the filter', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      final notes = NoteRepository(db);
      final id = await notes.create('Tagged guide');
      await notes.create('WPC unrelated');
      await NoteTagRepository(db).add(id, 'WPC');
    });
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [FlyLocalizationsDelegate()],
          home: Scaffold(body: GlobalSearchPalette()),
        ),
      ),
    );
    final input = find.byKey(const ValueKey('global-search-input'));
    await tester.enterText(input, 'WPC');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('search-tag-workspaceNote:wpc')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    expect(find.text('Tagged guide'), findsOneWidget);
    expect(find.text('WPC unrelated'), findsNothing);
    expect(find.byKey(const ValueKey('search-tag-filter')), findsOneWidget);
    await tester.tap(find.byTooltip('Clear tag filter'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    expect(find.text('WPC unrelated'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
