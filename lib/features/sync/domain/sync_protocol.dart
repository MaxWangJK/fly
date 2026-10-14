import 'dart:convert';

class SyncServerConfig {
  static const defaultBaseUrl = 'https://world-workshop.cn/api';
  static const officialFileEmail = 'max@ceiling-arts.com';
  static bool isOfficial(String input) =>
      validate(input).host.toLowerCase().replaceFirst(RegExp(r'\.$'), '') ==
      'world-workshop.cn';
  static bool allowsCloudFiles(String input, String? email) =>
      !isOfficial(input) || email?.trim().toLowerCase() == officialFileEmail;
  static String displayAddress(String input) =>
      validate(input).toString().replaceFirst(RegExp(r'^https?://'), '');
  static Uri validate(String input) {
    final address = input.trim();
    final official = RegExp(
      r'^world-workshop\.cn(?::\d+)?(?:/|$)',
      caseSensitive: false,
    ).hasMatch(address);
    final uri = Uri.tryParse(
      address.contains('://')
          ? address
          : '${official ? 'https' : 'http'}://$address',
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

enum SyncConnectionMode { cloud, lan }

class LanPairingPayload {
  const LanPairingPayload(this.endpoints, this.code, this.expiresAt);
  final List<String> endpoints;
  final String code;
  final DateTime expiresAt;
  String encode() => jsonEncode({
    'type': 'fly-lan-pair',
    'version': 1,
    'endpoints': endpoints,
    'code': code,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  });
  static LanPairingPayload decode(String raw, {DateTime? now}) {
    if (raw.length > 4096) throw const FormatException('二维码内容无效');
    final data = jsonObject(raw);
    if (data['type'] != 'fly-lan-pair' ||
        data['version'] != 1 ||
        data['endpoints'] is! List ||
        data['code'] is! String ||
        !RegExp(r'^\d{6}$').hasMatch(data['code'] as String)) {
      throw const FormatException('请扫描 Fly 电脑端的配对二维码');
    }
    final expires = DateTime.tryParse('${data['expiresAt']}');
    if (expires == null || !expires.isAfter(now ?? DateTime.now())) {
      throw const FormatException('二维码已过期，请在电脑端刷新');
    }
    final endpoints = (data['endpoints'] as List).map((value) {
      final uri = SyncServerConfig.validate('$value');
      if (!SyncServerConfig.isPrivateHost(uri.host) ||
          uri.host == 'localhost' ||
          uri.host == '127.0.0.1' ||
          uri.host == '::1') {
        throw const FormatException('二维码不包含有效的电脑局域网地址');
      }
      return uri.toString();
    }).toList();
    if (endpoints.isEmpty || endpoints.length > 8) {
      throw const FormatException('电脑地址无效');
    }
    return LanPairingPayload(endpoints, data['code'] as String, expires);
  }
}

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
