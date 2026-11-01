import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../files/data/managed_file_storage.dart';
import '../data/sync_outbox_repository.dart';
import '../data/sync_schema.dart';
import '../domain/sync_protocol.dart';
import '../domain/automatic_sync_merge.dart';
import 'file_transfer_scheduler.dart';
import 'lan_file_response.dart';
import 'lan_discovery_service.dart';

class LanHostService {
  LanHostService(this.outbox, this.root);
  final SyncOutboxRepository outbox;
  final String root;
  HttpServer? _server;
  Future<void> _queue = Future.value();
  final _fileScheduler = FileTransferScheduler();
  final _fileRequests = <Future<void>>{};
  final _discovery = LanDiscoveryHost();
  final _random = Random.secure();
  late final String hostToken = _token();
  String pairingCode = '';
  DateTime? pairingExpires;
  String? workspace;
  bool cloudActive = false, syncFiles = false;
  void Function()? onPairingChanged;
  LanSyncMode mode = LanSyncMode.bidirectional;
  final Map<String, List<DateTime>> _attempts = {};
  int get port => _server?.port ?? 8765;
  bool get running => _server != null;
  String _token() =>
      base64Url.encode(List.generate(32, (_) => _random.nextInt(256)));
  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  static bool _constantEqual(String a, String b) {
    final aa = utf8.encode(a), bb = utf8.encode(b);
    var difference = aa.length ^ bb.length;
    for (var i = 0; i < min(aa.length, bb.length); i++) {
      difference |= aa[i] ^ bb[i];
    }
    return difference == 0;
  }

  void rotatePairing() {
    pairingCode = '${100000 + _random.nextInt(900000)}';
    pairingExpires = DateTime.now().add(const Duration(minutes: 5));
    onPairingChanged?.call();
  }

  Future<List<String>> addresses() async => [
    for (final adapter in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    ))
      if (!RegExp(
        r'virtual|vmware|docker|vethernet|loopback',
        caseSensitive: false,
      ).hasMatch(adapter.name))
        for (final address in adapter.addresses)
          if (SyncServerConfig.isPrivateHost(address.address) &&
              !address.isLoopback)
            address.address,
  ];
  Future<void> start({int port = 8765}) async {
    if (port < 1 || port > 65535) throw ArgumentError('无效端口');
    workspace = await outbox.state('lanWorkspace');
    workspace ??= const Uuid().v4();
    await outbox.saveState('lanWorkspace', workspace!);
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    rotatePairing();
    server.listen((request) {
      if (request.uri.path.startsWith('/api/files/')) {
        if (_fileRequests.length >= 32) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          unawaited(request.response.close());
          return;
        }
        final upload = RegExp(r'/upload/([a-f0-9]{64})/')
            .firstMatch(request.uri.path);
        final task = _fileScheduler
            .run(() => _handle(request), key: upload?[1])
            .catchError((Object _) {});
        _fileRequests.add(task);
        unawaited(task.whenComplete(() => _fileRequests.remove(task)));
        return;
      }
      // All authority mutations and cursors share one serial queue.
      _queue = _queue.then((_) => _handle(request)).catchError((Object _) {});
    });
    await _discovery.start(
      workspace: workspace!,
      httpPort: server.port,
      tokenHash: (id) async =>
          (await outbox.db
                  .customSelect(
                    'SELECT token_hash FROM lan_devices WHERE id=? AND revoked=0',
                    variables: sqlVariables([id]),
                  )
                  .getSingleOrNull())
              ?.read<String>('token_hash'),
    );
    await outbox.db.customStatement(
      'UPDATE sync_conflicts SET resolved=1 WHERE resolved=0',
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _discovery.close();
    await server?.close(force: true);
    await _queue;
    await Future.wait(_fileRequests.toList());
    pairingCode = '';
  }

  Future<void> revoke(String id) => outbox.db.customStatement(
    'UPDATE lan_devices SET revoked=1 WHERE id=?',
    [id],
  );

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    final bytes = await _bytes(request, 8 * 1024 * 1024);
    return jsonObject(utf8.decode(bytes));
  }

  Future<List<int>> _bytes(HttpRequest request, int limit) async {
    final bytes = <int>[];
    await for (final chunk in request.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > limit) {
        throw const _LanError(413, '内容超过限制');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/api/health' && request.method == 'GET') {
        return await _respond(request, {'status': 'ok', 'apiVersion': 1});
      }
      if (path == '/api/lan/pair' && request.method == 'POST') {
        final ip = request.connectionInfo?.remoteAddress.address ?? '';
        final attempts = _attempts.putIfAbsent(ip, () => []);
        attempts.removeWhere(
          (t) => DateTime.now().difference(t).inSeconds > 60,
        );
        if (attempts.length >= 5) throw const _LanError(429, '配对尝试过于频繁');
        attempts.add(DateTime.now());
        if (_attempts.length > 1000) {
          _attempts.removeWhere(
            (_, a) =>
                a.isEmpty || DateTime.now().difference(a.last).inSeconds > 60,
          );
        }
        final body = await _body(request);
        if (pairingExpires == null ||
            DateTime.now().isAfter(pairingExpires!) ||
            !_constantEqual('${body['code']}', pairingCode)) {
          throw const _LanError(401, '配对码无效或已过期');
        }
        final id = const Uuid().v4(), token = _token();
        final name = '${body['deviceName'] ?? 'Mobile'}';
        if (name.length > 120) throw const _LanError(422, '设备名称过长');
        await outbox.db.customStatement(
          'INSERT INTO lan_devices(id,name,token_hash) VALUES(?,?,?)',
          [id, name, _hash(token)],
        );
        rotatePairing();
        return await _respond(request, {
          'deviceId': id,
          'token': token,
          'workspaceId': workspace,
          'mode': mode.name,
        });
      }
      final authorization =
          request.headers.value(HttpHeaders.authorizationHeader) ?? '';
      if (!authorization.startsWith('Bearer ')) {
        throw const _LanError(401, '需要配对');
      }
      final token = authorization.substring(7);
      final internal =
          request.connectionInfo?.remoteAddress.isLoopback == true &&
          _constantEqual(token, hostToken);
      final device = internal
          ? null
          : await outbox.db
                .customSelect(
                  'SELECT * FROM lan_devices WHERE token_hash=? AND revoked=0',
                  variables: sqlVariables([_hash(token)]),
                )
                .getSingleOrNull();
      if (!internal && device == null) throw const _LanError(401, '设备未受信任');
      final deviceId = internal ? 'desktop' : device!.read<String>('id');
      if (path == '/api/lan/info' && request.method == 'GET') {
        return await _respond(request, {
          'mode': mode.name,
          'desktop': internal,
          'cloudActive': cloudActive,
          'workspaceId': workspace,
          'deviceId': deviceId,
        });
      }
      if (path.startsWith('/api/sync/') && cloudActive) {
        throw const _LanError(409, '云同步已启用；云端协调记录，局域网仅传输文件');
      }
      if (path == '/api/sync/push' && request.method == 'POST') {
        if (!internal && mode == LanSyncMode.desktopToMobile) {
          throw const _LanError(403, '电脑 → 手机模式不接收手机修改');
        }
        final body = await _body(request);
        final mutations = body['mutations'] as List;
        if (mutations.isEmpty || mutations.length > 200) {
          throw const _LanError(422, '无效批量');
        }
        final results = await outbox.db.transaction(
          () async => [
            for (final raw in mutations)
              await _accept((raw as Map).cast<String, dynamic>(), deviceId),
          ],
        );
        return await _respond(request, {'results': results});
      }
      if ((path == '/api/sync/pull' || path == '/api/sync/bootstrap') &&
          request.method == 'GET') {
        final after =
            int.tryParse(request.uri.queryParameters['after'] ?? '0') ?? -1;
        final limit =
            int.tryParse(request.uri.queryParameters['limit'] ?? '100') ?? 0;
        if (after < 0 || limit < 1 || limit > 200) {
          throw const _LanError(422, '无效游标');
        }
        if (!internal && mode == LanSyncMode.mobileToDesktop) {
          return await _respond(request, {
            'changes': [],
            'nextCursor': after,
            'hasMore': false,
          });
        }
        final rows = await outbox.db
            .customSelect(
              'SELECT * FROM lan_changes WHERE seq>? ORDER BY seq LIMIT ?',
              variables: sqlVariables([after, limit + 1]),
            )
            .get();
        return await _respond(request, {
          'changes': [
            for (final r in rows.take(limit))
              {
                ...jsonObject(r.read<String>('data')),
                'seq': r.read<int>('seq'),
              },
          ],
          'nextCursor': rows.isEmpty
              ? after
              : rows[min(rows.length, limit) - 1].read<int>('seq'),
          'hasMore': rows.length > limit,
        });
      }
      if (path == '/api/sync/conflicts' && request.method == 'GET') {
        final rows = await outbox.db
            .customSelect(
              'SELECT data FROM sync_conflicts WHERE resolved=0 LIMIT 100',
            )
            .get();
        return await _respond(request, [
          for (final r in rows) jsonObject(r.read<String>('data')),
        ]);
      }
      if (RegExp(r'^/api/sync/conflicts/[a-f0-9-]{36}/resolve$')
              .hasMatch(path) &&
          request.method == 'POST') {
        await outbox.db.customStatement(
          'UPDATE sync_conflicts SET resolved=1 WHERE id=?',
          [path.split('/')[4]],
        );
        return await _respond(request, {'ok': true});
      }
      if (path.startsWith('/api/files/')) {
        if (!syncFiles) throw const _LanError(403, '局域网文件同步未开启');
        return await _files(request);
      }
      throw const _LanError(404, '接口不存在');
    } on _LanError catch (e) {
      await _respond(request, {'detail': e.message}, status: e.status);
    } on Object {
      await _respond(request, {'detail': '请求无效或同步失败'}, status: 400);
    }
  }

  Future<Map<String, dynamic>> _accept(
    Map<String, dynamic> mutation,
    String device,
  ) async {
    final entity = mutation['entityType'] as String;
    final id = mutation['recordId'] as String,
        mutationId = mutation['mutationId'] as String;
    const uuidPattern =
        r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$';
    final operation = mutation['operation'] as String;
    if (!syncTables.contains(entity) ||
        !RegExp(uuidPattern).hasMatch(id) ||
        !RegExp(uuidPattern).hasMatch(mutationId) ||
        !{'upsert', 'delete', 'restore'}.contains(operation)) {
      throw const _LanError(422, '无效同步协议');
    }
    final hash = _hash(jsonEncode(mutation));
    final prior = await outbox.db
        .customSelect(
          'SELECT * FROM lan_mutations WHERE mutation_id=?',
          variables: sqlVariables([mutationId]),
        )
        .getSingleOrNull();
    if (prior != null) {
      if (prior.read<String>('request_hash') != hash) {
        throw const _LanError(409, '重复变更 ID 的内容不同');
      }
      return jsonObject(prior.read<String>('result'));
    }
    final previous = await outbox.db
        .customSelect(
          'SELECT * FROM lan_records WHERE entity_type=? AND record_id=?',
          variables: sqlVariables([entity, id]),
        )
        .getSingleOrNull();
    final version = previous?.read<int>('version') ?? 0;
    final base = mutation['baseVersion'] as int;
    if (base < 0 || base > version) throw const _LanError(409, '无效基础版本');
    final payload = (mutation['payload'] as Map).cast<String, dynamic>();
    final fields = (mutation['changedFields'] as List).cast<String>();
    if (fields.length > 200 || fields.any((f) => !payload.containsKey(f))) {
      throw const _LanError(422, '无效字段');
    }
    final changed = <String>{};
    if (base < version) {
      final history = await outbox.db
          .customSelect('SELECT data FROM lan_changes')
          .get();
      for (final r in history) {
        final c = jsonObject(r.read<String>('data'));
        if (c['recordId'] == id &&
            c['entityType'] == entity &&
            (c['version'] as int) > base) {
          changed.addAll((c['changedFields'] as List).cast<String>());
          if (c['operation'] != 'upsert') changed.add('__lifecycle__');
        }
      }
    }
    final before = previous == null
        ? <String, dynamic>{}
        : jsonObject(previous.read<String>('data'));
    final clockKey = 'lanFieldClocks:$entity:$id';
    final clocks = jsonObject(await outbox.state(clockKey) ?? '{}');
    final incomingClocks = (mutation['fieldClocks'] as Map? ?? const {})
        .cast<String, dynamic>();
    final deleted = previous?.data['deleted_at'] as String?;
    final overlap = fields.toSet().intersection(changed)
      ..removeWhere(
        (f) =>
            {'updated_at', 'created_at', 'version'}.contains(f) ||
            before[f] == payload[f],
      );
    final deletionConflict =
        (deleted != null && operation == 'upsert') ||
        (operation == 'delete' && changed.isNotEmpty) ||
        changed.contains('__lifecycle__');
    final binaryConflict =
        entity == 'attachments' &&
        before['deletion_batch'] != 'permanent' &&
        overlap.contains('sha256');
    final conflictId = overlap.isNotEmpty || deletionConflict
        ? const Uuid().v4()
        : null;
    if (conflictId != null) {
      await outbox.storeConflicts([
        {
          'id': conflictId,
          'entityType': entity,
          'recordId': id,
          'fields': overlap.toList(),
          'localCandidate': payload,
          'serverCandidate': before,
          'kind': deletionConflict
              ? 'delete_update'
              : binaryConflict
              ? 'binary'
              : 'same_field',
          'deviceId': device,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'resolved': true,
        },
      ]);
      if (binaryConflict || (entity == 'note_blocks' && overlap.isNotEmpty)) {
        await _conflictCopy(
          entity,
          binaryConflict ? {...before, ...payload} : before,
          device,
        );
      }
    }
    final blocked =
        (entity == 'attachments' && before['deletion_batch'] == 'permanent') ||
        deleted != null &&
            operation != 'delete' &&
            !(operation == 'restore' && base == version);
    var current = <String, dynamic>{
      'entityType': entity,
      'recordId': id,
      'version': version,
      'data': before,
      'deletedAt': deleted,
      'fieldClocks': clocks,
    };
    if (!blocked && !binaryConflict) {
      final data = mergeRecordFields(
        before: before,
        payload: payload,
        fields: fields,
        concurrentFields: changed,
        clocks: clocks,
        incomingClocks: incomingClocks,
        mutationId: mutationId,
        nowMilliseconds: DateTime.now().millisecondsSinceEpoch,
      );
      if (const {'orders', 'tags', 'file_tags'}.contains(entity)) {
        final others = await outbox.db
            .customSelect(
              'SELECT data FROM lan_records WHERE entity_type=?',
              variables: sqlVariables([entity]),
            )
            .get();
        disambiguateSyncUniqueFields(
          entity,
          id,
          data,
          others.map((r) => jsonObject(r.read<String>('data'))),
        );
      }
      if (operation == 'delete' && version == 0) {
        data.addAll(payload);
      }
      final tombstone = operation == 'delete'
          ? DateTime.now().toUtc().toIso8601String()
          : null;
      if (data.containsKey('deleted_at')) {
        data['deleted_at'] = tombstone == null
            ? null
            : DateTime.parse(tombstone).millisecondsSinceEpoch ~/ 1000;
      }
      current = {
        'entityType': entity,
        'recordId': id,
        'version': version + 1,
        'data': data,
        'deletedAt': tombstone,
        'fieldClocks': clocks,
      };
      await outbox.db.customStatement(
        'INSERT INTO lan_records(entity_type,record_id,version,data,deleted_at) VALUES(?,?,?,?,?) ON CONFLICT(entity_type,record_id) DO UPDATE SET version=excluded.version,data=excluded.data,deleted_at=excluded.deleted_at',
        [entity, id, version + 1, jsonEncode(data), tombstone],
      );
      await outbox.db.customStatement(
        'INSERT INTO lan_changes(data) VALUES(?)',
        [
          jsonEncode({
            ...current,
            'operation': operation,
            'changedFields': fields,
          }),
        ],
      );
      await outbox.saveState(clockKey, jsonEncode(clocks));
    }
    final result = {
      'mutationId': mutationId,
      'status': 'accepted',
      'autoMerged': conflictId != null,
      'conflictId': conflictId,
      'record': current,
    };
    await outbox.db.customStatement(
      'INSERT INTO lan_mutations(mutation_id,request_hash,result) VALUES(?,?,?)',
      [mutationId, hash, jsonEncode(result)],
    );
    return result;
  }

  Future<void> _conflictCopy(
    String entity,
    Map<String, dynamic> candidate,
    String device,
  ) async {
    if (!candidate.containsKey('id')) return;
    final data = {...candidate, 'id': const Uuid().v4()};
    if (entity == 'attachments') {
      final name = '${data['original_name'] ?? 'file'}';
      final dot = name.lastIndexOf('.');
      final suffix =
          ' (conflict $device ${DateTime.now().toIso8601String().split('T').first})';
      final copied = dot > 0
          ? '${name.substring(0, dot)}$suffix${name.substring(dot)}'
          : '$name$suffix';
      data['original_name'] = copied;
      data['display_name'] = copied;
      data['file_name'] = copied;
    } else {
      data['sort_order'] = (data['sort_order'] as int? ?? 0) + 1;
    }
    final id = SyncOutboxRepository.identity(entity, jsonEncode([data['id']]));
    final record = {
      'entityType': entity,
      'recordId': id,
      'version': 1,
      'data': data,
      'deletedAt': null,
    };
    await outbox.db.customStatement(
      'INSERT INTO lan_records(entity_type,record_id,version,data,deleted_at) VALUES(?,?,1,?,NULL)',
      [entity, id, jsonEncode(data)],
    );
    await outbox.db.customStatement('INSERT INTO lan_changes(data) VALUES(?)', [
      jsonEncode({
        ...record,
        'operation': 'upsert',
        'changedFields': data.keys.toList(),
      }),
    ]);
  }

  Future<void> _files(HttpRequest request) async {
    final path = request.uri.path;
    final storage = ManagedFileStorage(root);
    if (path == '/api/files/upload/init' && request.method == 'POST') {
      final body = await _body(request);
      final hash = body['sha256'] as String, size = body['size'] as int;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
          size < 0 ||
          size > 2 * 1024 * 1024 * 1024) {
        throw const _LanError(422, '无效文件');
      }
      final blob = File(storage.absolute('sync_blobs/$hash'));
      if (await blob.exists() && await blob.length() == size) {
        return await _respond(request, {
          'exists': true,
          'chunkBytes': 4 * 1024 * 1024,
        });
      }
      final partial = File('${blob.path}.part');
      await outbox.saveState('lanUpload:$hash', '$size');
      return await _respond(request, {
        'exists': false,
        'uploadId': hash,
        'offset': await partial.exists() ? await partial.length() : 0,
        'chunkBytes': 4 * 1024 * 1024,
      });
    }
    final upload = RegExp(
      r'^/api/files/upload/([a-f0-9]{64})/(chunk|complete)$',
    ).firstMatch(path);
    if (upload != null) {
      final hash = upload[1]!;
      final size = int.tryParse(await outbox.state('lanUpload:$hash') ?? '');
      if (size == null) throw const _LanError(404, '上传会话不存在');
      final blob = File(storage.absolute('sync_blobs/$hash'));
      final partial = File('${blob.path}.part');
      await blob.parent.create(recursive: true);
      if (upload[2] == 'chunk' && request.method == 'PUT') {
        final offset =
            int.tryParse(request.uri.queryParameters['offset'] ?? '') ?? -1;
        final current = await partial.exists() ? await partial.length() : 0;
        final bytes = await _bytes(request, 4 * 1024 * 1024);
        if (offset != current ||
            bytes.isEmpty ||
            current + bytes.length > size) {
          throw const _LanError(409, '分片进度不一致');
        }
        final output = await partial.open(mode: FileMode.append);
        try {
          await output.writeFrom(bytes);
          await output.flush();
        } finally {
          await output.close();
        }
        return await _respond(request, {'offset': current + bytes.length});
      }
      if (upload[2] == 'complete' && request.method == 'POST') {
        if (await blob.exists()) {
          return await _respond(request, {'sha256': hash, 'size': size});
        }
        if (size == 0 && !await partial.exists()) await partial.create();
        if (!await partial.exists() ||
            await partial.length() != size ||
            (await sha256.bind(partial.openRead()).first).toString() != hash) {
          throw const _LanError(422, '文件校验失败');
        }
        await partial.rename(blob.path);
        return await _respond(request, {'sha256': hash, 'size': size});
      }
    }
    final download = RegExp(r'^/api/files/([a-f0-9-]{36})/download$')
        .firstMatch(path);
    if (download != null && request.method == 'GET') {
      final rows = await outbox.db
          .customSelect(
            'SELECT * FROM sync_metadata WHERE entity_type=? AND deleted_at IS NULL',
            variables: sqlVariables(['attachments']),
          )
          .get();
      for (final r in rows) {
        if (SyncOutboxRepository.identity(
              'attachments',
              r.read<String>('record_key'),
            ) !=
            download[1]) {
          continue;
        }
        final data = jsonObject(r.read<String>('payload'));
        final hash = data['sha256'] as String?;
        if (hash == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) break;
        final local = await (outbox.db.select(
          outbox.db.attachments,
        )..where((f) => f.id.equals(data['id'] as String))).getSingleOrNull();
        if (local == null) break;
        var file = File(storage.absolute(local.relativePath));
        if (!await file.exists()) {
          file = File(storage.absolute('sync_blobs/$hash'));
        }
        if (!await file.exists()) break;
        await serveLanFile(request, file, hash);
        return;
      }
      throw const _LanError(404, '文件内容仅存在于其它设备');
    }
    throw const _LanError(404, '文件接口不存在');
  }

  Future<void> _respond(
    HttpRequest request,
    Object data, {
    int status = 200,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }
}

class _LanError implements Exception {
  const _LanError(this.status, this.message);
  final int status;
  final String message;
}
