import 'dart:convert';
import 'dart:io';

import '../domain/sync_protocol.dart';

class SyncHttpException implements Exception {
  const SyncHttpException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => '同步服务器 ($status)：$message';
}

class CloudSyncTransport implements SyncTransport {
  CloudSyncTransport(String baseUrl, {this.token, this.onUnauthorized})
    : baseUrl = SyncServerConfig.validate(baseUrl);
  final Uri baseUrl;
  final Future<String?> Function()? token;
  final Future<void> Function()? onUnauthorized;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  Future<HttpClientResponse> _send(
    String method,
    String path, {
    Object? body,
    List<int>? bytes,
    bool retry = true,
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
      return _send(method, path, body: body, bytes: bytes, retry: false);
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
  }) async {
    final response = await _send('GET', path);
    if (response.statusCode != 200) {
      await _json(response);
      return;
    }
    final target = File(destination);
    await target.parent.create(recursive: true);
    final output = target.openWrite();
    try {
      var count = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 40))) {
        count += chunk.length;
        if (count > 2 * 1024 * 1024 * 1024) throw StateError('文件超过大小限制');
        output.add(chunk);
        onProgress?.call(count, response.contentLength);
      }
      await output.flush();
    } finally {
      await output.close();
    }
  }

  @override
  void close() => _client.close(force: true);
}

class LanSyncTransport extends CloudSyncTransport {
  LanSyncTransport(super.baseUrl, {required super.token});
}
