import 'dart:convert';
import 'dart:io';
import 'dart:async';

import '../domain/sync_protocol.dart';
import 'resumable_download.dart';

class SyncHttpException implements Exception {
  const SyncHttpException(this.status, this.message, {this.reason});
  final int status;
  final String message;
  final String? reason;
  @override
  String toString() => '同步服务器 ($status)：$message';
}

class CloudSyncTransport implements SyncTransport {
  CloudSyncTransport(
    String baseUrl, {
    this.token,
    this.onUnauthorized,
    this.resumeScope,
    Duration connectionTimeout = const Duration(seconds: 15),
  }) : baseUrl = SyncServerConfig.validate(baseUrl),
       _client = (HttpClient()..connectionTimeout = connectionTimeout);
  Uri baseUrl;
  final Future<String?> Function()? token;
  final Future<void> Function()? onUnauthorized;
  final String? resumeScope;
  final HttpClient _client;

  Future<HttpClientResponse> _send(
    String method,
    String path, {
    Object? body,
    List<int>? bytes,
    bool retry = true,
    Map<String, String> headers = const {},
  }) async {
    if (!path.startsWith('/') || path.startsWith('//')) {
      throw ArgumentError('Invalid API path');
    }
    final uri = Uri.parse('$baseUrl$path');
    final request = await _client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 20));
    request.followRedirects =
        false; // Credentials must never follow a changed origin.
    headers.forEach(request.headers.set);
    final access = await token?.call();
    if (access != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $access');
    }
    if (bytes != null) {
      request.headers.contentType = ContentType.binary;
      request.add(bytes);
    } else if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close().timeout(const Duration(seconds: 40));
    if (response.statusCode == 401 && retry && onUnauthorized != null) {
      await response.drain<void>();
      await onUnauthorized!();
      return _send(
        method,
        path,
        body: body,
        bytes: bytes,
        retry: false,
        headers: headers,
      );
    }
    return response;
  }

  Future<String> _boundedBody(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 40))) {
      if (bytes.length + chunk.length > 8 * 1024 * 1024) {
        throw StateError('服务器响应过大');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Future<Map<String, dynamic>> _json(HttpClientResponse response) async {
    final text = await _boundedBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? reason;
      try {
        final data = jsonDecode(text);
        final detail = data is Map ? data['detail'] : null;
        // Only known constant reasons may cross the transport boundary. Never
        // expose a server's echoed credentials, request bodies or tracebacks.
        if (const {
          'Graphical verification is incorrect',
          'Refresh the graphical verification',
          'Invalid or expired email code',
          'Account password is incorrect',
        }.contains(detail)) {
          reason = detail as String;
        }
      } on FormatException {
        // HTML proxy errors and arbitrary bodies still get the generic message.
      }
      // Do not include echoed payloads/tokens in errors shown or logged by the app.
      throw SyncHttpException(
        response.statusCode,
        switch (response.statusCode) {
          401 => '登录已过期',
          409 => '记录或账号状态冲突',
          413 => '内容超过限制',
          429 => '请求过于频繁，请稍后重试',
          _ => '请求失败',
        },
        reason: reason,
      );
    }
    final Object? data;
    try {
      data = jsonDecode(text);
    } on FormatException {
      throw const SyncHttpException(502, '服务器响应格式无效');
    }
    if (data is! List && data is! Map) {
      throw const SyncHttpException(502, '服务器响应格式无效');
    }
    return data is List
        ? {'items': data}
        : (data as Map).cast<String, dynamic>();
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
  }) async => _json(await _send(method, path, body: body));
  @override
  Future<Map<String, dynamic>> uploadChunk(
    String path,
    List<int> chunk,
  ) async => _json(await _send('PUT', path, bytes: chunk));
  @override
  Future<void> download(String path, String destination) =>
      downloadWithProgress(path, destination);
  Future<void> downloadWithProgress(
    String path,
    String destination, {
    void Function(int, int)? onProgress,
    String? expectedSha256,
    int? expectedSize,
  }) async {
    await receiveResumableFile(
      destination: destination,
      source: '${resumeScope ?? baseUrl.toString()}$path',
      sha256: expectedSha256,
      size: expectedSize,
      onProgress: onProgress,
      open: (headers) async {
        final response = await _send('GET', path, headers: headers);
        if (response.statusCode != 200 && response.statusCode != 206) {
          await _json(response);
        }
        return response;
      },
    );
  }

  @override
  void close() => _client.close(force: true);
}

class LanSyncTransport extends CloudSyncTransport {
  LanSyncTransport(
    super.baseUrl, {
    required super.token,
    super.connectionTimeout,
    super.resumeScope,
    this.reconnect,
  });
  final Future<String?> Function()? reconnect;
  Future<String?>? _reconnecting;
  Future<T> _connected<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SocketException {
      return _recover(action);
    } on TimeoutException {
      return _recover(action);
    } on HttpException {
      return _recover(action);
    }
  }

  Future<T> _recover<T>(Future<T> Function() action) async {
    final old = baseUrl;
    final endpoint = await (_reconnecting ??= Future.sync(
      () => reconnect?.call(),
    ).whenComplete(() => _reconnecting = null));
    if (endpoint == null || endpoint == old.toString()) {
      throw const SocketException('无法连接已配对电脑');
    }
    baseUrl = SyncServerConfig.validate(endpoint);
    return action();
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
  }) => _connected(() => super.request(method, path, body: body));
  @override
  Future<Map<String, dynamic>> uploadChunk(String path, List<int> chunk) =>
      _connected(() => super.uploadChunk(path, chunk));
  @override
  Future<void> downloadWithProgress(
    String path,
    String destination, {
    void Function(int, int)? onProgress,
    String? expectedSha256,
    int? expectedSize,
  }) => _connected(
    () => super.downloadWithProgress(
      path,
      destination,
      onProgress: onProgress,
      expectedSha256: expectedSha256,
      expectedSize: expectedSize,
    ),
  );
}
