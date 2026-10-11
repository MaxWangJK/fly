import 'dart:convert';

class SyncServerConfig {
  static const defaultBaseUrl = 'https://world-workshop.cn/api';
  static Uri validate(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.path.replaceFirst(RegExp(r'/$'), '') != '/api') {
      throw const FormatException('服务器地址须包含有效协议、主机、端口和 /api');
    }
    if (uri.scheme == 'http' && !isPrivateHost(uri.host)) {
      throw const FormatException('公网服务器必须使用 HTTPS');
    }
    return uri.replace(path: '/api');
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
