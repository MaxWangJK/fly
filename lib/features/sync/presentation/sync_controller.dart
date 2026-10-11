import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/data_root_providers.dart';
import '../../account/data/auth_service.dart';
import '../../tasks/presentation/task_providers.dart';
import '../data/cloud_sync_transport.dart';
import '../data/sync_outbox_repository.dart';
import '../data/sync_schema.dart';
import '../domain/sync_protocol.dart';
import '../services/file_sync_service.dart';
import '../services/device_service.dart';
import '../services/sync_conflict_service.dart';
import '../services/lan_host_service.dart';
import '../services/sync_engine.dart';
import '../services/sync_notification_service.dart';

final syncControllerProvider = ChangeNotifierProvider<SyncController>((ref) {
  final controller = SyncController(
    SyncOutboxRepository(ref.watch(databaseProvider)),
    ref.watch(dataRootPathProvider) ?? '',
  );
  unawaited(controller.initialize());
  return controller;
});

class SyncController extends ChangeNotifier {
  SyncController(this.outbox, this.root) : host = LanHostService(outbox, root) {
    auth = AuthService(server, root);
  }
  final SyncOutboxRepository outbox;
  final String root;
  final LanHostService host;
  late AuthService auth;
  SyncEngine? engine;
  SyncNotificationService? notifications;
  String server = SyncServerConfig.defaultBaseUrl;
  bool ready = false,
      busy = false,
      cloudEnabled = false,
      cloudFiles = false,
      lanFiles = false;
  String? error, lanEndpoint, lanToken, lanWorkspace;
  List<String> addresses = [];
  List<Map<String, dynamic>> devices = [], conflicts = [], trustedDevices = [];
  Map<String, int> counts = {};
  int lanPort = 8765;
  LanSyncMode mode = LanSyncMode.bidirectional;
  bool _disposed = false;
  Future<void> initialize() async {
    try {
      server = await outbox.state('server') ?? server;
      SyncServerConfig.validate(server);
      auth = AuthService(server, root);
      if (root.isNotEmpty) await auth.restore();
      cloudFiles = await outbox.state('cloudFiles') == 'true';
      lanFiles = await outbox.state('lanFiles') == 'true';
      lanPort = int.tryParse(await outbox.state('lanPort') ?? '') ?? 8765;
      final savedMode = await outbox.state('lanMode');
      mode = LanSyncMode.values.firstWhere(
        (m) => m.name == savedMode,
        orElse: () => LanSyncMode.bidirectional,
      );
      lanEndpoint = await outbox.state('lanEndpoint');
      lanWorkspace = await outbox.state('lanRemoteWorkspace');
      if (lanEndpoint != null) {
        lanToken = await auth.storage.read(
          key: 'fly-lan-${AuthService(lanEndpoint!, root).storageKey}',
        );
      }
      counts = await outbox.initialCounts();
      ready = true;
      if (await outbox.state('cloudEnabled') == 'true' && auth.userId != null) {
        await _enableCloud();
      }
      if (await outbox.state('lanHostEnabled') == 'true') await _startHost();
      if (!cloudEnabled && !host.running && lanToken != null) {
        await _startLanClient();
      }
    } on Object catch (e) {
      error = _errorText(e);
      ready = true;
    }
    _notify();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
    } on Object catch (e) {
      error = _errorText(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  String _errorText(Object error) => '$error'.replaceFirst(
    RegExp(r'^(Bad state: |Invalid argument\(s\): |FormatException: )'),
    '',
  );

  Future<void> login(
    bool register,
    String email,
    String password,
    String confirm,
  ) => run(() async {
    await auth.authenticate(
      register: register,
      email: email,
      password: password,
      confirm: confirm,
    );
    counts = await outbox.initialCounts();
    await refreshDetails();
  });
  Future<void> logout() => run(() async {
    await _stopEngine();
    cloudEnabled = false;
    host.cloudActive = false;
    await outbox.saveState('cloudEnabled', 'false');
    await auth.logout();
    devices = [];
    conflicts = [];
  });
  Future<void> configureServer(String value) => run(() async {
    if (cloudEnabled) throw StateError('请先关闭云同步再修改服务器');
    final checked = SyncServerConfig.validate(value).toString();
    server = checked;
    await outbox.saveState('server', checked);
    auth = AuthService(server, root);
    await auth.restore();
    devices = [];
    conflicts = [];
  });
  Future<void> testConnection([String? value]) => run(() async {
    final transport = CloudSyncTransport(value ?? server);
    try {
      final response = await transport.request('GET', '/health');
      if (response['status'] != 'ok' || response['apiVersion'] != 1) {
        throw StateError('服务器协议不兼容');
      }
    } finally {
      transport.close();
    }
  });
  Future<void> setCloud(bool value) => run(() async {
    if (value) {
      await _enableCloud();
    } else {
      await _stopEngine();
      cloudEnabled = false;
      host.cloudActive = false;
    }
    await outbox.saveState('cloudEnabled', '$value');
  });
  Future<void> _enableCloud() async {
    if (auth.userId == null) throw StateError('请先登录');
    await outbox.bind('cloud:$server:${auth.userId}');
    await _stopEngine();
    final transport = CloudSyncTransport(
      server,
      token: auth.accessToken,
      onUnauthorized: auth.refresh,
    );
    engine = SyncEngine(
      outbox: outbox,
      transport: transport,
      cursorKey: 'cloudCursor',
      files: FileSyncService(outbox.db, root, transport),
      syncFiles: cloudFiles,
    );
    engine!.addListener(_changed);
    cloudEnabled = true;
    _configureLanFiles();
    host.cloudActive = true;
    engine!.start();
    notifications = SyncNotificationService(
      auth,
      () => unawaited(engine?.synchronize()),
    );
    unawaited(notifications!.connect());
  }

  Future<void> setFiles({bool? cloud, bool? lan}) => run(() async {
    if (cloud != null) {
      cloudFiles = cloud;
      await outbox.saveState('cloudFiles', '$cloud');
    }
    if (lan != null) {
      lanFiles = lan;
      host.syncFiles = lan;
      await outbox.saveState('lanFiles', '$lan');
    }
    engine?.syncFiles = cloudEnabled ? cloudFiles : lanFiles;
    _configureLanFiles();
  });
  Future<void> setHost(bool value, int port) => run(() async {
    if (value) {
      lanPort = port;
      await _startHost();
    } else {
      if (!cloudEnabled) await _stopEngine();
      await host.stop();
    }
    await outbox.saveState('lanHostEnabled', '$value');
    await outbox.saveState('lanPort', '$port');
  });
  Future<void> _startHost() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      throw StateError('局域网服务仅支持电脑');
    }
    host.mode = mode;
    host.syncFiles = lanFiles;
    host.cloudActive = cloudEnabled;
    await host.start(port: lanPort);
    try {
      addresses = await host.addresses();
      if (!cloudEnabled) {
        await outbox.bind('lan:${host.workspace}');
        await _stopEngine();
        final transport = LanSyncTransport(
          'http://127.0.0.1:$lanPort/api',
          token: () async => host.hostToken,
        );
        engine = SyncEngine(
          outbox: outbox,
          transport: transport,
          cursorKey: 'lanCursor',
          files: FileSyncService(outbox.db, root, transport),
          syncFiles: lanFiles,
        );
        engine!.addListener(_changed);
        engine!.start();
      }
      await refreshDetails();
    } on Object {
      await host.stop();
      rethrow;
    }
  }

  Future<void> setMode(LanSyncMode value) => run(() async {
    mode = value;
    host.mode = value;
    await outbox.saveState('lanMode', value.name);
  });
  Future<void> pair(String endpoint, String code) => run(() async {
    final checked = SyncServerConfig.validate(endpoint).toString();
    final transport = LanSyncTransport(checked, token: () async => null);
    try {
      final response = await transport.request(
        'POST',
        '/lan/pair',
        body: {'code': code.trim(), 'deviceName': Platform.localHostname},
      );
      final workspace = response['workspaceId'] as String;
      if (!cloudEnabled) await outbox.bind('lan:$workspace');
      lanEndpoint = checked;
      lanToken = response['token'] as String;
      lanWorkspace = workspace;
      await auth.storage.write(
        key: 'fly-lan-${AuthService(checked, root).storageKey}',
        value: lanToken,
      );
      await outbox.saveState('lanEndpoint', checked);
      await outbox.saveState('lanRemoteWorkspace', workspace);
      if (!cloudEnabled) await _startLanClient();
      _configureLanFiles();
    } finally {
      transport.close();
    }
  });
  Future<void> _startLanClient() async {
    await outbox.bind('lan:$lanWorkspace');
    await _stopEngine();
    final transport = LanSyncTransport(
      lanEndpoint!,
      token: () async => lanToken,
    );
    engine = SyncEngine(
      outbox: outbox,
      transport: transport,
      cursorKey: 'lanCursor',
      files: FileSyncService(outbox.db, root, transport),
      syncFiles: lanFiles,
    );
    engine!.addListener(_changed);
    engine!.start();
  }

  void _configureLanFiles() {
    final active = engine;
    if (active == null || !cloudEnabled) return;
    active.lanFiles?.transport.close();
    active.lanFiles = lanFiles && lanToken != null && lanEndpoint != null
        ? FileSyncService(
            outbox.db,
            root,
            LanSyncTransport(lanEndpoint!, token: () async => lanToken),
          )
        : null;
  }

  void resume() {
    if (ready) unawaited(engine?.synchronize());
  }

  void _changed() {
    _notify();
  }

  Future<void> refreshDetails() async {
    if (auth.userId != null) {
      final transport = CloudSyncTransport(
        server,
        token: auth.accessToken,
        onUnauthorized: auth.refresh,
      );
      try {
        devices = await DeviceService(transport).list();
        conflicts = (await transport.request(
          'GET',
          '/sync/conflicts',
        ))['items'].cast<Map<String, dynamic>>();
      } finally {
        transport.close();
      }
    } else {
      final rows = await outbox.db
          .customSelect(
            'SELECT data FROM sync_conflicts WHERE resolved=0 LIMIT 100',
          )
          .get();
      conflicts = [
        for (final row in rows) jsonObject(row.read<String>('data')),
      ];
    }
    final trusted = await outbox.db
        .customSelect('SELECT id,name,revoked FROM lan_devices')
        .get();
    trustedDevices = [for (final row in trusted) row.data];
    _notify();
  }

  Future<void> resolve(Map<String, dynamic> conflict, bool useOther) =>
      run(() async {
        if (engine == null || !engine!.enabled) {
          throw StateError('请先开启同步再处理冲突');
        }
        final entity = conflict['entityType'] as String;
        final keyRow = await outbox.db
            .customSelect(
              'SELECT record_key,sync_version,payload FROM sync_metadata WHERE entity_type=? AND sync_id=?',
              variables: sqlVariables([entity, conflict['recordId']]),
            )
            .getSingleOrNull();
        if (keyRow == null) throw StateError('请先同步此记录');
        if (useOther) {
          final candidate =
              (conflict[{'binary', 'delete_update'}.contains(conflict['kind'])
                          ? 'localCandidate'
                          : 'serverCandidate']
                      as Map)
                  .cast<String, dynamic>();
          final canonical = jsonObject(keyRow.read<String>('payload'));
          final data = {...canonical, ...candidate};
          final fields = conflict['kind'] == 'delete_update'
              ? data.keys.toList()
              : (conflict['fields'] as List)
                    .where((f) => data.containsKey(f))
                    .cast<String>()
                    .toList();
          final operation = conflict['kind'] == 'delete_update'
              ? 'restore'
              : 'upsert';
          // Queue an explicit, current-version choice; retain audit candidates permanently.
          await outbox.db.customStatement(
            'INSERT INTO sync_outbox(mutation_id,entity_type,record_key,base_version,changed_fields,payload,operation,created_at) VALUES(?,?,?,?,?,?,?,?)',
            [
              const Uuid().v4(),
              entity,
              keyRow.read<String>('record_key'),
              keyRow.read<int>('sync_version'),
              jsonEncode(fields),
              jsonEncode(data),
              operation,
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
            ],
          );
          await engine?.synchronize();
          if (engine?.status == '同步失败') throw StateError('同步失败，冲突尚未解决');
        }
        final transport = cloudEnabled
            ? CloudSyncTransport(
                server,
                token: auth.accessToken,
                onUnauthorized: auth.refresh,
              )
            : LanSyncTransport(
                host.running ? 'http://127.0.0.1:$lanPort/api' : lanEndpoint!,
                token: () async => host.running ? host.hostToken : lanToken,
              );
        try {
          await transport.request(
            'POST',
            '/sync/conflicts/${conflict['id']}/resolve',
          );
        } finally {
          transport.close();
        }
        await SyncConflictService(outbox.db).resolve(
          conflict['id'] as String,
          entity,
          conflict['recordId'] as String,
        );
        await refreshDetails();
      });
  Future<void> _stopEngine() async {
    notifications?.dispose();
    notifications = null;
    final old = engine;
    engine = null;
    if (old != null) {
      old.removeListener(_changed);
      await old.shutdown();
      old.dispose();
    }
  }

  Future<void> revokeDevice(String id) => run(() async {
    if (id == auth.deviceId) {
      throw StateError('当前设备请使用退出登录');
    }
    final transport = CloudSyncTransport(
      server,
      token: auth.accessToken,
      onUnauthorized: auth.refresh,
    );
    try {
      await DeviceService(transport).revoke(id);
    } finally {
      transport.close();
    }
    await refreshDetails();
  });

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    notifications?.dispose();
    engine?.dispose();
    unawaited(host.stop());
    super.dispose();
  }
}
