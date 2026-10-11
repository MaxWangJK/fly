import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/sync/data/cloud_sync_transport.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/data/sync_schema.dart';
import 'package:fly/features/sync/domain/sync_protocol.dart';
import 'package:fly/features/sync/services/lan_host_service.dart';
import 'package:fly/features/sync/services/sync_conflict_service.dart';

void main() {
  late AppDatabase db;
  late SyncOutboxRepository outbox;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureBuiltInData();
    outbox = SyncOutboxRepository(db);
    await db.customStatement('DELETE FROM sync_outbox');
  });
  tearDown(() => db.close());

  test('business write and mutation roll back together', () async {
    final customers = DriftCustomerRepository(db);
    await expectLater(
      db.transaction(() async {
        await customers.createCustomer(name: 'Rolled back');
        expect(await outbox.pendingCount(), greaterThan(0));
        throw StateError('rollback');
      }),
      throwsStateError,
    );
    expect(await outbox.pendingCount(), 0);
    expect(
      await (db.select(
        db.customers,
      )..where((r) => r.name.equals('Rolled back'))).get(),
      isEmpty,
    );
  });

  test(
    'captures relationship hard delete and preserves immutable retry',
    () async {
      final customers = DriftCustomerRepository(db);
      final customer = await customers.createCustomer(name: 'Jack');
      final tag = await customers.findOrCreateTag('Offline');
      await customers.setCustomerTags(customer.id, [tag.id]);
      final prepared = await outbox.prepare();
      expect(
        prepared.any((m) => m['entityType'] == 'customer_tag_links'),
        isTrue,
      );
      final before = prepared.firstWhere((m) => m['entityType'] == 'customers');
      await db.customStatement('UPDATE customers SET phone=? WHERE id=?', [
        '123',
        customer.id,
      ]);
      final retry = (await outbox.prepare()).firstWhere(
        (m) => m['mutationId'] == before['mutationId'],
      );
      expect(retry, before);
      await db.customStatement(
        'DELETE FROM customer_tag_links WHERE customer_id=?',
        [customer.id],
      );
      final tombstone = await db
          .customSelect(
            "SELECT * FROM sync_outbox WHERE entity_type='customer_tag_links' AND operation='delete'",
          )
          .get();
      expect(tombstone, hasLength(1));
    },
  );

  test(
    'migration adds only sync tables and preserves schema17 local records',
    () async {
      final folder = await Directory.systemTemp.createTemp('fly-v18-');
      final file = File('${folder.path}/fly.db');
      var migrated = AppDatabase(NativeDatabase(file));
      try {
        await migrated.ensureBuiltInData();
        final jack = await DriftCustomerRepository(migrated)
            .createCustomer(name: 'Preserved Jack');
        final triggers = await migrated
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'sync_%'",
            )
            .get();
        for (final t in triggers) {
          await migrated.customStatement(
            'DROP TRIGGER "${t.read<String>('name')}"',
          );
        }
        final tables = await migrated
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE 'sync_%' OR name LIKE 'lan_%')",
            )
            .get();
        for (final t in tables) {
          await migrated.customStatement(
            'DROP TABLE "${t.read<String>('name')}"',
          );
        }
        await migrated.customStatement('PRAGMA user_version=17');
        await migrated.close();
        migrated = AppDatabase(NativeDatabase(file));
        expect(
          (await (migrated.select(
            migrated.customers,
          )..where((r) => r.id.equals(jack.id))).getSingle()).name,
          'Preserved Jack',
        );
        final queue = SyncOutboxRepository(migrated);
        await queue.bind('cloud:test:user');
        final pending = await queue.pendingCount();
        await queue.bind('cloud:test:user');
        expect(await queue.pendingCount(), pending);
        expect(
          await migrated.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await migrated.close();
        await folder.delete(recursive: true);
      }
    },
  );

  test(
    'remote apply preserves queued local fields and suppresses echo mutations',
    () async {
      final jack = await DriftCustomerRepository(db)
          .createCustomer(name: 'Jack');
      final creation = (await outbox.prepare()).firstWhere(
        (m) => m['entityType'] == 'customers',
      );
      final data = (creation['payload'] as Map).cast<String, dynamic>();
      await outbox.acknowledge([
        {
          'mutationId': creation['mutationId'],
          'status': 'accepted',
          'record': {
            'entityType': 'customers',
            'recordId': creation['recordId'],
            'version': 1,
            'data': data,
            'deletedAt': null,
          },
        },
      ]);
      await db.customStatement('UPDATE customers SET phone=? WHERE id=?', [
        'offline phone',
        jack.id,
      ]);
      final count = await outbox.pendingCount();
      await outbox.applyPage({
        'changes': [
          {
            'entityType': 'customers',
            'recordId': creation['recordId'],
            'version': 2,
            'data': {...data, 'address': 'Manila'},
            'deletedAt': null,
          },
        ],
        'nextCursor': 2,
      }, 'testCursor');
      final row = await (db.select(
        db.customers,
      )..where((r) => r.id.equals(jack.id))).getSingle();
      expect(row.phone, 'offline phone');
      expect(row.address, 'Manila');
      expect(await outbox.pendingCount(), count);
      expect(await outbox.state('testCursor'), '2');
    },
  );

  test('invalid remote apply rolls back cursor with its page', () async {
    await expectLater(
      outbox.applyPage({
        'changes': [
          {'entityType': 'untrusted_table', 'recordId': 'x'},
        ],
        'nextCursor': 100,
      }, 'cursor'),
      throwsStateError,
    );
    expect(await outbox.state('cursor'), isNull);
    expect(
      (await db.customSelect('SELECT applying FROM sync_control').getSingle())
          .read<int>('applying'),
      0,
    );
  });

  test('conflict service preserves candidates and reflects unresolved record status', () async {
    final jack = await DriftCustomerRepository(db).createCustomer(name: 'Jack');
    final queued = (await outbox.prepare()).firstWhere(
      (m) => m['entityType'] == 'customers',
    );
    await outbox.storeConflicts([
      {
        'id': 'test-conflict',
        'entityType': 'customers',
        'recordId': queued['recordId'],
        'serverCandidate': {'phone': 'A'},
        'localCandidate': {'phone': 'B'},
      },
    ]);
    final status = await db
        .customSelect(
          'SELECT sync_status FROM sync_metadata WHERE entity_type=? AND record_key=?',
          variables: sqlVariables([
            'customers',
            jsonEncode([jack.id]),
          ]),
        )
        .getSingle();
    expect(status.read<String>('sync_status'), 'conflict');
    await SyncConflictService(db)
        .resolve('test-conflict', 'customers', queued['recordId'] as String);
    final saved = await db
        .customSelect('SELECT data,resolved FROM sync_conflicts')
        .getSingle();
    expect(
      jsonObject(saved.read<String>('data'))['localCandidate']['phone'],
      'B',
    );
    expect(saved.read<int>('resolved'), 1);
  });

  test('server configuration accepts HTTP/HTTPS and rejects invalid URLs', () {
    expect(
      SyncServerConfig.validate('https://world-workshop.cn/api').host,
      'world-workshop.cn',
    );
    expect(
      SyncServerConfig.validate('http://192.168.1.20:8765/api').port,
      8765,
    );
    for (final url in [
      'ftp://example.com/api',
      'https://a:b@example.com/api',
      'https://example.com/api?q=x',
    ]) {
      expect(() => SyncServerConfig.validate(url), throwsFormatException);
    }
  });

  test(
    'LAN pairing, idempotency, merge, cursor and one-way permissions',
    () async {
      final root = await Directory.systemTemp.createTemp('fly-lan-');
      final host = LanHostService(outbox, root.path);
      final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = reserved.port;
      await reserved.close();
      await host.start(port: port);
      final unauthenticated = LanSyncTransport(
        'http://127.0.0.1:$port/api',
        token: () async => null,
      );
      try {
        await expectLater(
          unauthenticated.request('GET', '/sync/pull'),
          throwsA(isA<SyncHttpException>()),
        );
        await expectLater(
          unauthenticated.request('POST', '/lan/pair', body: {'code': 'wrong'}),
          throwsA(isA<SyncHttpException>()),
        );
        final paired = await unauthenticated.request(
          'POST',
          '/lan/pair',
          body: {'code': host.pairingCode, 'deviceName': 'Phone'},
        );
        final client = LanSyncTransport(
          'http://127.0.0.1:$port/api',
          token: () async => paired['token'] as String,
        );
        try {
          final jack = await DriftCustomerRepository(db)
              .createCustomer(name: 'LAN Jack');
          final mutation = (await outbox.prepare()).firstWhere(
            (m) => m['entityType'] == 'customers',
          );
          final first = await client.request(
            'POST',
            '/sync/push',
            body: {
              'mutations': [mutation],
            },
          );
          final retry = await client.request(
            'POST',
            '/sync/push',
            body: {
              'mutations': [mutation],
            },
          );
          expect(retry, first);
          final pulled = await client.request('GET', '/sync/pull?after=0');
          expect(
            (pulled['changes'] as List).single['data']['name'],
            'LAN Jack',
          );
          expect(pulled['nextCursor'], 1);
          host.mode = LanSyncMode.desktopToMobile;
          await expectLater(
            client.request(
              'POST',
              '/sync/push',
              body: {
                'mutations': [mutation],
              },
            ),
            throwsA(isA<SyncHttpException>()),
          );
          host.mode = LanSyncMode.mobileToDesktop;
          expect(
            (await client.request('GET', '/sync/pull'))['changes'],
            isEmpty,
          );
          await host.revoke(paired['deviceId'] as String);
          await expectLater(
            client.request('GET', '/sync/pull'),
            throwsA(isA<SyncHttpException>()),
          );
          expect(
            (await (db.select(
              db.customers,
            )..where((r) => r.id.equals(jack.id))).getSingle()).name,
            'LAN Jack',
          );
        } finally {
          client.close();
        }
      } finally {
        unauthenticated.close();
        await host.stop();
        await root.delete(recursive: true);
      }
    },
  );
}
