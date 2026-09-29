import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/notes/data/note_repository.dart';
import 'package:fly/features/notes/domain/note_block.dart';
import 'package:fly/shared/search/global_search_service.dart';

void main() {
  test('V10 searches customer notes independently of name and searches readable note blocks', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final customers = DriftCustomerRepository(db);
      final jack = await customers.createCustomer(name: 'Jack');
      await customers.saveCustomer(
        jack.copyWith(notes: 'Special negotiation phrase'),
      );
      final notes = NoteRepository(db);
      final id = await notes.create('销售知识');
      await notes.save(
        id,
        title: '销售知识',
        expectedRevision: 1,
        blocks: [
          NoteBlock(
            id: 'secret-block-id',
            type: 'paragraph',
            content: {'text': 'A unique quotation guide'},
          ),
          NoteBlock(
            id: 'table',
            type: 'table',
            content: {
              'rows': [
                ['市场分析', 'Cebu'],
              ],
            },
          ),
        ],
      );
      final search = GlobalSearchService(db);
      expect(
        (await search.search(
          'negotiation',
        )).any((r) => r.type == SearchResultType.note && r.entityId == jack.id),
        true,
      );
      expect(
        (await search.search('quotation')).any((r) => r.entityId == id),
        true,
      );
      expect((await search.search('Cebu')).any((r) => r.entityId == id), true);
      expect(await search.search('secret-block-id'), isEmpty);
      await customers.softDeleteCustomer(jack.id);
      expect(await search.search('negotiation'), isEmpty);
    } finally {
      await db.close();
    }
  });
}
