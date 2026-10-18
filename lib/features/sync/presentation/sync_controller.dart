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
import '../services/sync_workspace_binding.dart';

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
    host.onPairingChanged = _notify;
  }
  final SyncOutboxRepository outbox;
  final String root;
  final LanHostService host;
  late AuthService auth;
  SyncEngine? engine;
  SyncNotificationService? notifications;
  String server = SyncServerConfig.defaultBaseUrl;
  bool ready = false, busy = false, cloudEnabled = false;
  bool get cloudFiles => SyncServerConfig.allowsCloudFiles(server, auth.email);
  bool get lanFiles => true;
  SyncConnectionMode connectionMode = SyncConnectionMode.lan;
  bool get isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  LanPairingPayload? get pairingPayload =>
      host.running && addresses.isNotEmpty && host.pairingExpires != null
      ? LanPairingPayload(
          addresses.take(8).map((a) => 'http://$a:$lanPort/api').toList(),
          host.pairingCode,
          host.pairingExpires!,
        )
      : null;
  String? error, lanEndpoint, lanToken, lanWorkspace;
  List<String> addresses = [];
  List<Map<String, dynamic>> devices = [], conflicts = [], trustedDevices = [];
  Map<String, int> counts = {};
  int lanPort = 8765;
  LanSyncMode mode = LanSyncMode.bidirectional;
  bool _disposed = false;
  bool _foreground = true;
  Future<void> _lifecycle = Future.value();
  bool get connected =>
      engine?.enabled == true &&
      engine?.lastSuccess != null &&
      engine?.error == null;
  bool get connecting => engine?.running == true && !connected;
  Future<void> initialize() async {
    try {
      server = await outbox.state('server') ?? server;
      SyncServerConfig.validate(server);
      auth = AuthService(server, root);
      if (root.isNotEmpty) await auth.restore();
      lanPort = int.tryParse(await outbox.state('lanPort') ?? '') ?? 8765;
      lanEndpoint = await outbox.state('lanEndpoint');
      lanWorkspace = await outbox.state('lanRemoteWorkspace');
      if (lanEndpoint != null) {
        lanToken = await auth.storage.read(
          key: 'fly-lan-${AuthService(lanEndpoint!, root).storageKey}',
        );
      }
      counts = await outbox.initialCounts();
      ready = true;
      final savedHost = await outbox.state('lanHostEnabled') == 'true';
      // The product now exposes desktop pairing only. Keep saved cloud identity
      // and workspace contexts intact, but do not reconnect a hidden mode.
      connectionMode = SyncConnectionMode.lan;
      await outbox.saveState('syncConnectionMode', 'lan');
      await outbox.saveState('cloudEnabled', 'false');
      if (connectionMode == SyncConnectionMode.lan) {
        if (savedHost && !isMobile) await _startHost();
        if (!host.running &&
            lanToken != null &&
            await outbox.state('lanClientEnabled') != 'false') {
          await _startLanClient();
        }
      }
    } on Object catch (e) {
      error = _errorText(e);
      ready = true;
    }
    if (!_foreground && isMobile) await _stopEngine();
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
    if (connectionMode == SyncConnectionMode.cloud) {
      engine?.syncFiles = cloudFiles;
    }
    await refreshDetails();
  });
  Future<void> logout() => run(() async {
    if (cloudEnabled) await _stopEngine();
    cloudEnabled = false;
    host.cloudActive = false;
    await outbox.saveState('cloudEnabled', 'false');
    await auth.logout();
    devices = [];
    conflicts = [];
  });
  Future<void> configureServer(String value) => run(() async {
    if (cloudEnabled) throw StateError('请先关闭云同步再修改服务器');
    final checked = _serverInput(value).toString();
    await _saveServer(checked);
  });
  Uri _serverInput(String value) {
    final checked = SyncServerConfig.validate(value);
    if (!value.contains('://') &&
        SyncServerConfig.displayAddress(server).toLowerCase() ==
            SyncServerConfig.displayAddress(value).toLowerCase()) {
      return Uri.parse(server);
    }
    return checked;
  }

  Future<void> _saveServer(String checked) async {
    if (checked == server) return;
    server = checked;
    await outbox.saveState('server', checked);
    auth = AuthService(server, root);
    await auth.restore();
    devices = [];
    conflicts = [];
  }

  Future<void> testConnection([String? value]) => run(() async {
    final input = value ?? server;
    final preferred = _serverInput(input);
    final candidates = [preferred];
    if (!input.contains('://') && !SyncServerConfig.isOfficial(input)) {
      candidates.add(
        preferred.replace(
          scheme: preferred.scheme == 'https' ? 'http' : 'https',
          port: preferred.hasPort ? preferred.port : null,
        ),
      );
    }
    Object? last;
    for (final candidate in candidates) {
      final transport = CloudSyncTransport(candidate.toString());
      try {
        final response = await transport.request('GET', '/health');
        if (response['status'] != 'ok' || response['apiVersion'] != 1) {
          throw StateError('服务器协议不兼容');
        }
        if (!cloudEnabled) await _saveServer(candidate.toString());
        return;
      } on Object catch (e) {
        last = e;
      } finally {
        transport.close();
      }
    }
    throw StateError('无法连接同步服务器：$last');
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
    if (connectionMode != SyncConnectionMode.cloud) throw StateError('请先选择云同步');
    if (auth.userId == null) throw StateError('请先登录');
    await _stopEngine();
    await SyncWorkspaceBinding(outbox).activate('cloud:$server:${auth.userId}');
    if (_disposed || (isMobile && !_foreground)) return;
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
      failureLimit: isMobile ? 3 : null,
    );
    engine!.addListener(_changed);
    cloudEnabled = true;
    host.cloudActive = true;
    engine!.start();
    notifications = SyncNotificationService(
      auth,
      () => unawaited(engine?.synchronize()),
    );
    unawaited(notifications!.connect());
  }

  Future<void> selectConnectionMode(SyncConnectionMode value) => run(() async {
    if (connectionMode == value) return;
    await _stopEngine();
    await host.stop();
    cloudEnabled = false;
    host.cloudActive = false;
    connectionMode = value;
    await outbox.saveState('cloudEnabled', 'false');
    await outbox.saveState('lanHostEnabled', 'false');
    await outbox.saveState('lanClientEnabled', 'false');
    await outbox.saveState('syncConnectionMode', value.name);
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
    if (connectionMode != SyncConnectionMode.lan) {
      throw StateError('请先选择电脑与手机同步');
    }
    if (host.running) return;
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
        await _stopEngine();
        await SyncWorkspaceBinding(outbox).activate('lan:${host.workspace}');
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
          failureLimit: isMobile ? 3 : null,
          pollInterval: const Duration(seconds: 2),
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
  Future<void> pair(String endpoint, String code) =>
      run(() => _pair(endpoint, code));
  Future<void> pairQr(String raw) => run(() async {
    final payload = LanPairingPayload.decode(raw);
    Object? last;
    for (final endpoint in payload.endpoints) {
      try {
        await _pair(endpoint, payload.code);
        return;
      } on SocketException catch (e) {
        last = e;
      } on TimeoutException catch (e) {
        last = e;
      }
    }
    throw StateError('无法连接电脑，请确认处于同一局域网并允许防火墙端口：$last');
  });
  Future<void> _pair(String endpoint, String code) async {
    if (connectionMode != SyncConnectionMode.lan) {
      throw StateError('请先选择电脑与手机同步');
    }
    final checked = SyncServerConfig.validate(endpoint).toString();
    final transport = LanSyncTransport(checked, token: () async => null);
    try {
      final response = await transport.request(
        'POST',
        '/lan/pair',
        body: {'code': code.trim(), 'deviceName': Platform.localHostname},
      );
      final workspace = response['workspaceId'] as String;
      if (!cloudEnabled) {
        await _stopEngine();
        await SyncWorkspaceBinding(outbox).activate('lan:$workspace');
      }
      lanEndpoint = checked;
      lanToken = response['token'] as String;
      lanWorkspace = workspace;
      await auth.storage.write(
        key: 'fly-lan-${AuthService(checked, root).storageKey}',
        value: lanToken,
      );
      await outbox.saveState('lanEndpoint', checked);
      await outbox.saveState('lanRemoteWorkspace', workspace);
      await outbox.saveState('lanClientEnabled', 'true');
      if (!cloudEnabled) await _startLanClient();
      final checkedTransport = LanSyncTransport(
        checked,
        token: () async => lanToken,
      );
      try {
        await checkedTransport.request('GET', '/lan/info');
      } finally {
        checkedTransport.close();
      }
    } finally {
      transport.close();
    }
  }

  Future<void> setLanClient(bool enabled) => run(() async {
    if (enabled) {
      if (lanToken == null || lanEndpoint == null) {
        throw StateError('请先扫描电脑二维码');
      }
      await _startLanClient();
    } else {
      await _stopEngine();
    }
    await outbox.saveState('lanClientEnabled', '$enabled');
  });
  Future<void> _startLanClient() async {
    await _stopEngine();
    await SyncWorkspaceBinding(outbox).activate('lan:$lanWorkspace');
    if (_disposed || (isMobile && !_foreground)) return;
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
      failureLimit: isMobile ? 3 : null,
      pollInterval: const Duration(seconds: 2),
    );
    engine!.addListener(_changed);
    engine!.start();
  }

  Future<void> suspend() {
    if (!isMobile) return Future.value();
    _foreground = false;
    notifications?.dispose();
    engine?.stop();
    engine?.transport.close();
    return _lifecycle = _lifecycle.then((_) => _stopEngine());
  }

  Future<void> resume() {
    _foreground = true;
    return _lifecycle = _lifecycle.then((_) async {
      if (!ready || _disposed || !_foreground) return;
      if (!isMobile) {
        await engine?.synchronize();
        return;
      }
      await connectNow(automatic: true);
    });
  }

  Future<void> connectNow({bool automatic = false}) => run(() async {
    if (!_foreground || _disposed) return;
    if (engine?.enabled == true) {
      await engine!.synchronize();
      return;
    }
    if (connectionMode == SyncConnectionMode.lan &&
        lanToken != null &&
        lanEndpoint != null) {
      if (automatic && await outbox.state('lanClientEnabled') == 'false') {
        return;
      }
      await _startLanClient();
      await outbox.saveState('lanClientEnabled', 'true');
    } else if (connectionMode == SyncConnectionMode.cloud &&
        auth.userId != null) {
      if (automatic && await outbox.state('cloudEnabled') != 'true') return;
      await _enableCloud();
      await outbox.saveState('cloudEnabled', 'true');
    } else if (!automatic) {
      throw StateError('请在同步设置扫描电脑二维码，或在电脑开启同步服务');
    }
  });

  void _changed() {
    if (isMobile && engine?.enabled == false) {
      notifications?.dispose();
      notifications = null;
    }
    _notify();
  }

  Future<void> refreshDetails() async {
    if (connectionMode == SyncConnectionMode.cloud && auth.userId != null) {
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
