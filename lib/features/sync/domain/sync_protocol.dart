import 'dart:convert';

class SyncServerConfig {
  static const defaultBaseUrl = 'https://world-workshop.cn/api';
  static Uri validate(String input) {
    final address = input.trim();
    final uri = Uri.tryParse(
      address.contains('://') ? address : 'http://$address',
    );
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535 ||
        address.isEmpty ||
        RegExp(
          r'/(?:\.|%2e){1,2}(?:/|$)',
          caseSensitive: false,
        ).hasMatch(address)) {
      throw const FormatException('请填写有效的 HTTP/HTTPS 域名或 IP，可包含端口');
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.isNotEmpty &&
        (uri.pathSegments.any((part) => part == '.' || part == '..') ||
            !path.endsWith('/api'))) {
      throw const FormatException('自定义 API 路径须以 /api 结尾');
    }
    return uri.replace(path: path.isEmpty ? '/api' : path);
  }

  static Uri websocketUrl(String input) {
    final base = validate(input);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      port: base.port,
      path: '${base.path}/ws',
    );
  }

  static bool isPrivateHost(String host) {
    if (host == 'localhost' || host == '::1') return true;
    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) {
      return false;
    }
    return parts[0] == 10 ||
        parts[0] == 127 ||
        (parts[0] == 192 && parts[1] == 168) ||
        (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31);
  }
}

enum LanSyncMode { bidirectional, desktopToMobile, mobileToDesktop }

abstract interface class SyncTransport {
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
  });
  Future<void> download(String path, String destination);
  Future<Map<String, dynamic>> uploadChunk(String path, List<int> chunk);
  void close();
}

Map<String, dynamic> jsonObject(String source) =>
    (jsonDecode(source) as Map).cast<String, dynamic>();
