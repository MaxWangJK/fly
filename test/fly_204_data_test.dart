import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/database/app_database.dart';
import 'package:fly/features/calendar/presentation/mobile_calendar_drag.dart';
import 'package:fly/features/customers/data/drift_customer_repository.dart';
import 'package:fly/features/files/data/file_batch_actions.dart';
import 'package:fly/features/files/data/file_browser_preferences.dart';
import 'package:fly/features/files/data/file_browser_query.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/sync/data/sync_outbox_repository.dart';
import 'package:fly/features/sync/services/file_transfer_inventory.dart';
import 'package:fly/features/tasks/data/drift_task_repository.dart';
import 'package:fly/features/tasks/domain/task_list_path.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Directory root;
  late ManagedFileStorage storage;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureBuiltInData();
    root = await Directory.systemTemp.createTemp('fly-204-data-');
    storage = ManagedFileStorage(root.path);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  Future<void> file(
    String id,
    List<int> bytes, {
    String name = 'quote.pdf',
  }) async {
    final path = 'files/$id/$name';
    final physical = File(storage.absolute(path));
    await physical.parent.create(recursive: true);
    await physical.writeAsBytes(bytes);
    await ManagedFileRepository(db).commit(
      ImportedFile(
        id: id,
        relativePath: path,
        name: name,
        size: bytes.length,
        sha256: id.padRight(64, '0'),
      ),
    );
  }

  test('batch share copies distinct same-name files and cleans its temporary bytes', () async {
    await file('a', [1, 2]);
    await file('b', [3, 4]);
    final share = await FileBatchActions(db, storage).prepareShare({'a', 'b'});
    expect(share.files.map((f) => f.name).toSet(), {
      'quote.pdf',
      'quote (2).pdf',
    });
    expect(await File(share.files[0].path).readAsBytes(), [1, 2]);
    expect(await File(share.files[1].path).readAsBytes(), [3, 4]);
    await share.cleanup();
    for (final f in share.files) {
      expect(await File(f.path).exists(), isFalse);
    }
    expect(await File(storage.absolute('files/a/quote.pdf')).exists(), isTrue);
    await ManagedFileRepository(db).rename('a', 'Revised');
    final renamed = await FileBatchActions(db, storage).prepareShare({'a'});
    expect(renamed.files.single.name, 'Revised.pdf');
    await renamed.cleanup();
  });
  test(
    'batch share blocks all items when one selected file is unavailable',
    () async {
      await file('a', [1]);
      await file('b', [2]);
      await File(storage.absolute('files/b/quote.pdf')).delete();
      await expectLater(
        FileBatchActions(db, storage).prepareShare({'a', 'b'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('1 个文件尚未下载'),
          ),
        ),
      );
      expect(
        await Directory(storage.absolute('cache/share')).exists(),
        isFalse,
      );
    },
  );
  test('old deferred share copies expire without deleting current shares or original files', () async {
    await file('a', [1]);
    await File(storage.absolute('files/a/quote.pdf'))
        .setLastModified(DateTime.now().subtract(const Duration(days: 7)));
    final old = await FileBatchActions(db, storage).prepareShare({'a'});
    expect(
      DateTime.now().difference(
        await File(old.files.single.path).lastModified(),
      ),
      lessThan(const Duration(minutes: 1)),
    );
    await File(old.files.single.path)
        .setLastModified(DateTime.now().subtract(const Duration(days: 2)));
    await file('b', [2]);
    final current = await FileBatchActions(db, storage).prepareShare({'b'});
    expect(await File(old.files.single.path).exists(), isFalse);
    expect(await File(current.files.single.path).exists(), isTrue);
    expect(await File(storage.absolute('files/a/quote.pdf')).exists(), isTrue);
    await current.cleanup();
  });
  test('batch delete reports partial errors, soft deletion preserves bytes and purge removes them', () async {
    await file('a', [1]);
    await file('b', [2]);
    final actions = FileBatchActions(db, storage);
    final shared = await actions.prepareShare({'a', 'b'});
    final deleted = await actions.delete({'a', 'b', 'missing'});
    expect(deleted.completed, {'a', 'b'});
    expect(deleted.errors.keys, ['missing']);
    expect(await File(storage.absolute('files/a/quote.pdf')).exists(), isTrue);
    final purged = await actions.delete({'a', 'b'}, permanent: true);
    expect(purged.errors, isEmpty);
    expect(purged.completed, {'a', 'b'});
    expect(await File(storage.absolute('files/a/quote.pdf')).exists(), isFalse);
    for (final copy in shared.files) {
      expect(await File(copy.path).exists(), isFalse);
    }
    expect(
      await FileBrowserQuery(db)
          .watch(collection: FileCollection.deleted)
          .first,
      isEmpty,
    );
  });
  test('preferences persist last values, separate device profiles and discard stale tags', () async {
    final tag = await ManagedFileRepository(db).createTag('Live file tag');
    final crm = await DriftCustomerRepository(db).findOrCreateTag('Priority');
    await db.customStatement('DELETE FROM sync_outbox');
    final phone = FileBrowserPreferencesStore(db, phone: true),
        desktop = FileBrowserPreferencesStore(db, phone: false);
    expect((await phone.load()).view, 'small');
    expect((await desktop.load()).view, 'small');
    await desktop.save(const FileBrowserPreferences(view: 'list'));
    expect((await desktop.load()).view, 'list');
    await Future.wait([
      phone.save(const FileBrowserPreferences(view: 'small')),
      phone.save(
        FileBrowserPreferences(
          view: 'list',
          sort: FileSort.name,
          imagesFirst: false,
          collection: FileCollection.customers,
          fileTags: {tag, 'removed'},
          customerTags: {crm.id, 'removed'},
        ),
      ),
    ]);
    final saved = await FileBrowserPreferencesStore(db, phone: true).load();
    expect(saved.view, 'list');
    expect(saved.sort, FileSort.name);
    expect(saved.imagesFirst, isFalse);
    expect(saved.fileTags, {tag});
    expect(saved.customerTags, {crm.id});
    expect(saved.collection, FileCollection.customers);
    expect((await desktop.load()).imagesFirst, isTrue);
    expect(await SyncOutboxRepository(db).pendingCount(), 0);
  });
  test('inventory distinguishes local unconfirmed files, pending downloads and unknown sources', () async {
    await file('a', [1]);
    await file('b', [2]);
    await File(storage.absolute('files/b/quote.pdf')).delete();
    var counts = await FileTransferInventory.load(db, root.path);
    expect(counts.uploads, 1);
    expect(counts.downloads, 1);
    expect(counts.waitingForSource, 0);
    final a = (await ManagedFileRepository(db).find('a'))!;
    await SyncOutboxRepository(db)
        .saveState(remoteFileStateKey('local', a.sha256!), 'true');
    await (db.update(db.attachments)..where((f) => f.id.equals('b'))).write(
      const AttachmentsCompanion(sha256: Value(null)),
    );
    counts = await FileTransferInventory.load(db, root.path);
    expect(counts.uploads, 0);
    expect(counts.downloads, 1);
    expect(counts.waitingForSource, 1);
  });
  test('inventory counts a new remote revision as a download and external size changes as uploads', () async {
    await file('a', [1]);
    final outbox = SyncOutboxRepository(db);
    final old = (await ManagedFileRepository(db).find('a'))!;
    final newerHash = 'b'.padRight(64, '0');
    await outbox.saveState('localBlob:a', old.sha256!);
    await outbox.saveState(remoteFileStateKey('local', newerHash), 'true');
    await (db.update(db.attachments)..where((f) => f.id.equals('a'))).write(
      AttachmentsCompanion(sha256: Value(newerHash)),
    );
    var counts = await FileTransferInventory.load(db, root.path);
    expect(counts.downloads, 1);
    expect(counts.uploads, 0);
    await outbox.saveState('localBlob:a', newerHash);
    await File(storage.absolute(old.relativePath)).writeAsBytes([1, 2]);
    counts = await FileTransferInventory.load(db, root.path);
    expect(counts.downloads, 0);
    expect(counts.uploads, 1);
  });
  test(
    'purging the last copy forgets remote confirmation so a reimport is queued',
    () async {
      await file('a', [1]);
      final repo = ManagedFileRepository(db), outbox = SyncOutboxRepository(db);
      final hash = (await repo.find('a'))!.sha256!;
      await outbox.saveState(remoteFileStateKey('local', hash), 'true');
      await outbox.saveState(remoteFileStateKey('other-server', hash), 'true');
      await FileBatchActions(db, storage).delete({'a'});
      await FileBatchActions(db, storage).delete({'a'}, permanent: true);
      expect(await outbox.state(remoteFileStateKey('local', hash)), isNull);
      expect(
        await outbox.state(remoteFileStateKey('other-server', hash)),
        isNull,
      );
      await file('a-again', [1]);
      await (db.update(db.attachments)..where((f) => f.id.equals('a-again')))
          .write(AttachmentsCompanion(sha256: Value(hash)));
      expect((await FileTransferInventory.load(db, root.path)).uploads, 1);
    },
  );
  test(
    'pending record count groups multiple edits of the same record',
    () async {
      final repo = DriftTaskRepository(db), outbox = SyncOutboxRepository(db);
      await db.customStatement('DELETE FROM sync_outbox');
      final task = await repo.createTask(title: 'Initial');
      await repo.saveTask(task.copyWith(title: 'Edited'));
      await repo.saveTask(task.copyWith(title: 'Edited again'));
      expect(await outbox.pendingCount(), greaterThan(1));
      expect(await outbox.pendingRecordCount(), 1);
    },
  );
  test('timed drag preserves cross-midnight duration and calendar-day changes preserve time', () async {
    final repo = DriftTaskRepository(db);
    final task = await repo.createTask(
      title: 'Night',
      dueDate: DateTime(2026, 10, 14, 1),
    );
    final timed = task.copyWith(
      startDate: DateTime(2026, 10, 13, 23),
      isAllDay: false,
    );
    final moved = shiftCalendarTask(
      timed,
      DateTime(2026, 10, 13, 23),
      DateTime(2026, 10, 16, 10, 15),
      time: true,
    );
    expect(moved.startDate, DateTime(2026, 10, 16, 10, 15));
    expect(moved.dueDate, DateTime(2026, 10, 16, 12, 15));
    final dateOnly = shiftCalendarTask(
      timed,
      DateTime(2026, 10, 13),
      DateTime(2026, 11, 2),
    );
    expect(dateOnly.startDate, DateTime(2026, 11, 2, 23));
    expect(dateOnly.dueDate, DateTime(2026, 11, 3, 1));
  });
  test(
    'all-day drag keeps inclusive span, completion and recurrence',
    () async {
      final task = (await DriftTaskRepository(db).createTask(
        title: 'Trip',
        dueDate: DateTime(2026, 10, 15),
      )).copyWith(startDate: DateTime(2026, 10, 13), recurrenceRule: 'daily');
      final moved = shiftCalendarTask(
        task,
        DateTime(2026, 10, 13),
        DateTime(2026, 11, 1, 15),
        time: true,
      );
      expect(moved.startDate, DateTime(2026, 11, 1));
      expect(moved.dueDate, DateTime(2026, 11, 3));
      expect(moved.isAllDay, isTrue);
      expect(moved.recurrenceRule, task.recurrenceRule);
      expect(moved.status, task.status);
    },
  );
  test(
    'list breadcrumb includes ancestors and safely handles an orphan',
    () async {
      final repo = DriftTaskRepository(db);
      final parent = await repo.createList('Work');
      final child = await repo.createList('Delivery', parentId: parent.id);
      final nested = await repo.createList('Today', parentId: child.id);
      final lists = await repo.watchLists().first;
      expect(taskListPath(lists, nested.id), ['Work', 'Delivery', 'Today']);
      expect(
        taskListPath(lists.where((l) => l.id != parent.id).toList(), nested.id),
        ['Delivery', 'Today'],
      );
    },
  );
}
