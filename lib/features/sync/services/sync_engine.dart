import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/sync_outbox_repository.dart';
import '../data/cloud_sync_transport.dart';
import '../data/sync_schema.dart';
import '../domain/sync_protocol.dart';
import 'file_sync_service.dart';

class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this.outbox,
    required this.transport,
    required this.cursorKey,
    required this.files,
    this.syncFiles = false,
  });
  final SyncOutboxRepository outbox;
  final SyncTransport transport;
  final String cursorKey;
  final FileSyncService files;
  FileSyncService? lanFiles;
  bool syncFiles, enabled = false, running = false;
  String status = '未开启同步';
  String? error;
  DateTime? lastSuccess;
  int pending = 0, conflictCount = 0;
  Timer? _timer, _debounce;
  StreamSubscription? _writes;
  Future<void>? _inFlight;
  bool _disposed = false;
  void start() {
    enabled = true;
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(synchronize()),
    );
    _writes ??= outbox.db.tableUpdates().listen((updates) {
      if (updates.any((u) => syncTables.contains(u.table))) {
        _debounce?.cancel();
        _debounce = Timer(
          const Duration(seconds: 1),
          () => unawaited(synchronize()),
        );
      }
    });
    unawaited(synchronize());
  }

  void stop() {
    enabled = false;
    _timer?.cancel();
    _debounce?.cancel();
    status = '未开启同步';
    _notify();
  }

  Future<void> synchronize() {
    if (!enabled || _disposed) return Future.value();
    return _inFlight ??= _sync().whenComplete(() => _inFlight = null);
  }

  Future<void> _sync() async {
    running = true;
    status = '正在同步';
    error = null;
    _notify();
    try {
      var pushEnabled = true, pullEnabled = true;
      if (transport is LanSyncTransport) {
        final info = await transport.request('GET', '/lan/info');
        final desktop = info['desktop'] == true;
        pushEnabled =
            info['cloudActive'] != true &&
            (desktop
                ? info['mode'] != 'mobileToDesktop'
                : info['mode'] != 'desktopToMobile');
        pullEnabled =
            info['cloudActive'] != true &&
            (desktop || info['mode'] != 'mobileToDesktop');
      }
      // Upload bounded blobs first so accepted metadata/conflict copies have content.
      if (syncFiles && pushEnabled) {
        await files.synchronize(uploadOnly: true);
      }
      if (lanFiles != null && pushEnabled) {
        await lanFiles!.synchronize(uploadOnly: true);
      }
      // Keep cycles bounded; large backlogs continue automatically without blocking UI.
      for (var batch = 0; batch < 20 && enabled && pushEnabled; batch++) {
        final mutations = await outbox.prepare();
        if (mutations.isEmpty) break;
        final ack = await transport.request(
          'POST',
          '/sync/push',
          body: {'mutations': mutations},
        );
        await outbox.acknowledge(ack['results'] as List);
      }
      var cursor = int.parse(await outbox.state(cursorKey) ?? '0');
      for (var page = 0; page < 100 && enabled && pullEnabled; page++) {
        final data = await transport.request(
          'GET',
          '/sync/pull?after=$cursor&limit=100',
        );
        final next = data['nextCursor'] as int;
        if (next < cursor || (data['hasMore'] == true && next == cursor)) {
          throw StateError('无效同步游标');
        }
        await outbox.applyPage(data, cursorKey);
        cursor = next;
        if (data['hasMore'] != true) break;
      }
      pending = await outbox.pendingCount();
      final conflicts = await transport.request('GET', '/sync/conflicts');
      await outbox.storeConflicts(conflicts['items'] as List);
      conflictCount = (conflicts['items'] as List).length;
      final deferred =
          (await outbox.db
                  .customSelect('SELECT count(*) AS n FROM sync_incoming')
                  .getSingle())
              .read<int>('n');
      if (deferred > 0) throw StateError('有 $deferred 条记录等待关联数据或重复值处理');
      if (syncFiles) {
        await files.synchronize(
          uploadEnabled: pushEnabled,
          downloadEnabled: pullEnabled,
        );
      }
      if (lanFiles != null) {
        await lanFiles!.synchronize();
      }
      lastSuccess = DateTime.now();
      await outbox.saveState(
        '$cursorKey:lastSuccess',
        lastSuccess!.toIso8601String(),
      );
      status = conflictCount > 0
          ? '有 $conflictCount 项同步冲突'
          : pending > 0
          ? '正在同步'
          : '已同步';
    } on SocketException {
      status = '离线';
      error = '本地数据已保存，网络恢复后自动重试';
    } on Object catch (e) {
      status = '同步失败';
      error = '$e';
    } finally {
      running = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> shutdown() async {
    stop();
    await _writes?.cancel();
    await _inFlight;
    transport.close();
    lanFiles?.transport.close();
  }

  @override
  void dispose() {
    _disposed = true;
    enabled = false;
    _timer?.cancel();
    _debounce?.cancel();
    unawaited(_writes?.cancel());
    transport.close();
    lanFiles?.transport.close();
    super.dispose();
  }
}
