import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/services/sync_workspace_binding.dart';

void main() {
  test('mode switching preserves immutable retries, cursor and current local edits', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.ensureBuiltInData();
      final outbox = SyncOutboxRepository(db);
      final binding = SyncWorkspaceBinding(outbox);
      final jack = await DriftCustomerRepository(db)
          .createCustomer(name: 'Jack');
      await binding.activate('cloud:synthetic:user-a');
      final frozen = (await outbox.prepare()).firstWhere(
        (r) => r['entityType'] == 'customers',
      );
      await outbox.saveState('cloudCursor', '42');
      await binding.activate('lan:synthetic-desktop');
      await db.customStatement('UPDATE customers SET address=? WHERE id=?', [
        'New address while using LAN',
        jack.id,
      ]);
      await binding.activate('cloud:synthetic:user-a');
      expect(await outbox.state('cloudCursor'), '42');
      expect(
        (await outbox.prepare()).firstWhere(
          (r) => r['entityType'] == 'customers',
        ),
        frozen,
      );
      await outbox.acknowledge([
        {
          'mutationId': frozen['mutationId'],
          'status': 'accepted',
          'record': {
            'entityType': 'customers',
            'recordId': frozen['recordId'],
            'version': 1,
            'data': frozen['payload'],
            'deletedAt': null,
          },
        },
      ]);
      final next = (await outbox.prepare()).firstWhere(
        (r) => r['entityType'] == 'customers',
      );
      expect(next['payload']['address'], 'New address while using LAN');
      expect(next['baseVersion'], 1);
      final local = await (db.select(
        db.customers,
      )..where((r) => r.id.equals(jack.id))).getSingle();
      expect(local.address, 'New address while using LAN');
      await expectLater(
        binding.activate('cloud:synthetic:user-b'),
        throwsStateError,
      );
      expect(await outbox.state('workspace'), 'cloud:synthetic:user-a');
    } finally {
      await db.close();
    }
  });
}
