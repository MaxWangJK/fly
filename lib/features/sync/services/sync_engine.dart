import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/sync_outbox_repository.dart';
import '../data/cloud_sync_transport.dart';
import '../data/sync_schema.dart';
import '../domain/sync_protocol.dart';
import 'file_sync_service.dart';
import '../../files/data/permanent_file_deletion.dart';
import '../../files/data/managed_file_storage.dart';

class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this.outbox,
    required this.transport,
    required this.cursorKey,
    required this.files,
    this.syncFiles = false,
    this.failureLimit,
    this.pollInterval = const Duration(minutes: 5),
    this.automaticMergeRequired = false,
  }) {
    files.onProgress = _notify;
  }
  final int? failureLimit;
  final Duration pollInterval;
  final bool automaticMergeRequired;
  int consecutiveFailures = 0;
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
  Future<void>? _inFlight, _exchangeFlight;
  bool _canPush = true, _canPull = true;
  Object? _backgroundError;
  bool _disposed = false;
  bool _resyncRequested = false;
  void start() {
    enabled = true;
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _schedule());
    _writes ??= outbox.db.tableUpdates().listen((updates) {
      if (updates.any((u) => syncTables.contains(u.table))) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), _schedule);
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
    final current = _inFlight;
    if (current != null) {
      // A write or remote hint can arrive after this cycle has already pulled.
      // Join the current operation and retain one follow-up cycle.
      _resyncRequested = true;
      return current;
    }
    return _inFlight = _syncRequested().whenComplete(() => _inFlight = null);
  }

  Future<void> _syncRequested() async {
    do {
      _resyncRequested = false;
      await _sync();
    } while (_resyncRequested && enabled && !_disposed && error == null);
  }

  Future<void> _sync() async {
    running = true;
    status = '正在同步';
    error = null;
    _backgroundError = null;
    _notify();
    try {
      if (automaticMergeRequired) {
        final health = await transport.request('GET', '/health');
        if ((health['capabilities'] as Map?)?['automaticMerge'] != true) {
          throw StateError('请先将云服务器升级到支持自动合并的同步版本');
        }
      }
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
      _canPush = pushEnabled;
      _canPull = pullEnabled;
      // Publish business changes before slow file I/O. Missing bytes are a
      // durable waiting state; content checks still gate final file availability.
      await _exchange(pushEnabled, pullEnabled);
      // Upload bounded blobs first so accepted metadata/conflict copies have content.
      if (syncFiles && pushEnabled) {
        await files.synchronize(uploadOnly: true);
      }
      if (lanFiles != null && pushEnabled) {
        await lanFiles!.synchronize(uploadOnly: true);
      }
      await _exchange(pushEnabled, pullEnabled);
      if (!enabled || _disposed) return;
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
      await PermanentFileDeletion(
        outbox.db,
        ManagedFileStorage(files.root),
      ).cleanup();
      if (!enabled || _disposed) return;
      await _exchangeFlight;
      if (_backgroundError != null) {
        throw StateError('数据同步暂未完成：$_backgroundError');
      }
      consecutiveFailures = 0;
      lastSuccess = DateTime.now();
      await outbox.saveState(
        '$cursorKey:lastSuccess',
        lastSuccess!.toIso8601String(),
      );
      await outbox.saveState(
        await outbox.successStateKey(cursorKey),
        lastSuccess!.toIso8601String(),
      );
      status = conflictCount > 0
          ? '有 $conflictCount 项同步冲突'
          : syncFiles && files.waiting > 0
          ? '数据已同步，${files.waiting} 个文件等待其它设备提供内容'
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
      if (error != null && enabled) {
        consecutiveFailures++;
        if (failureLimit != null && consecutiveFailures >= failureLimit!) {
          stop();
          transport.close();
          lanFiles?.transport.close();
          status = "连接失败，已停止重试";
        }
      }
      _notify();
    }
  }

  void _schedule() {
    if (!enabled || _disposed) return;
    if (running && files.phase != 'idle') {
      unawaited(
        _exchange(_canPush, _canPull).catchError((Object error) {
          _backgroundError = error;
          this.error = '$error';
          _notify();
        }),
      );
    } else {
      unawaited(synchronize());
    }
  }

  Future<void> _exchange(bool pushEnabled, bool pullEnabled) =>
      _exchangeFlight ??= _exchangeData(
        pushEnabled,
        pullEnabled,
      ).whenComplete(() => _exchangeFlight = null);

  Future<void> _exchangeData(bool pushEnabled, bool pullEnabled) async {
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
      pending = await outbox.pendingCount();
      _notify();
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
    if (_backgroundError != null && error == '$_backgroundError') error = null;
    _backgroundError = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> shutdown() async {
    stop();
    await _writes?.cancel();
    transport.close();
    lanFiles?.transport.close();
    await _inFlight;
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
    files.onProgress = null;
    super.dispose();
  }
}
