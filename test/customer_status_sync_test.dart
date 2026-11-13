import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/customers/import/customer_import_service.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';

void main() {
  test(
    'imported definitions, edits and deletion apply on another device',
    () async {
      final source = AppDatabase(NativeDatabase.memory());
      final peer = AppDatabase(NativeDatabase.memory());
      try {
        await source.ensureBuiltInData();
        await peer.ensureBuiltInData();
        await peer.customStatement('DELETE FROM sync_outbox');
        final outgoing = SyncOutboxRepository(source),
            incoming = SyncOutboxRepository(peer);
        var cursor = 0;
        Future<void> transfer() async {
          final mutations = await outgoing.prepare();
          final records = [
            for (final change in mutations)
              {
                'entityType': change['entityType'],
                'recordId': change['recordId'],
                'version': (change['baseVersion'] as int) + 1,
                'data': change['payload'],
                'deletedAt': null,
              },
          ];
          await incoming.applyPage({
            'changes': records.reversed.toList(),
            'nextCursor': ++cursor,
          }, 'status-test');
          await outgoing.acknowledge([
            for (var i = 0; i < mutations.length; i++)
              {
                'mutationId': mutations[i]['mutationId'],
                'status': 'accepted',
                'record': records[i],
              },
          ]);
        }

        final result = await CustomerImportService(source).import(
          requireProfile: true,
          rows: const [
            CustomerImportRow(
              rowNumber: 2,
              status: CustomerImportRowStatus.ready,
              values: {
                CustomerImportField.name: 'Synced partner',
                CustomerImportField.country: 'Canada',
                CustomerImportField.category: 'Platinum',
                CustomerImportField.status: 'Pending visit',
              },
            ),
          ],
        );
        expect(result.created, 1);
        await transfer();
        final remote = DriftCustomerRepository(peer);
        final customer = (await remote
            .watchCustomer(result.firstCustomerId!)
            .first)!;
        final statusId = customer.statusId!;
        expect(
          (await remote.watchCategories().first)
              .singleWhere((c) => c.id == customer.categoryId)
              .name,
          'Platinum',
        );
        expect(
          (await remote.watchStatuses().first)
              .singleWhere((s) => s.id == statusId)
              .name,
          'Pending visit',
        );
        final repo = DriftCustomerRepository(source);
        await repo.renameStatus(statusId, 'Visit booked');
        await repo.setStatusActive(statusId, active: false);
        await transfer();
        expect(
          (await remote.watchStatuses().first).any((s) => s.id == statusId),
          isFalse,
        );
        expect(
          (await remote.watchStatuses(includeInactive: true).first)
              .singleWhere((s) => s.id == statusId)
              .name,
          'Visit booked',
        );
        expect(
          (await remote.watchCustomer(customer.id).first)!.statusId,
          statusId,
        );
        expect(await incoming.pendingCount(), 0);
      } finally {
        await source.close();
        await peer.close();
      }
    },
  );
}
