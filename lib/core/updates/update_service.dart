import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../config/app_version.dart';
import '../../config/service_endpoints.dart';

class FlyVersion implements Comparable<FlyVersion> {
  const FlyVersion(this.major, this.minor, this.patch, [this.build = 0]);
  final int major, minor, patch, build;
  factory FlyVersion.parse(String input, {int? build}) {
    final match = RegExp(
      r'^(\d{1,5})\.(\d{1,5})(?:\.(\d{1,5}))?(?:\+(\d{1,9}))?$',
    ).firstMatch(input);
    if (match == null || (build != null && build < 0)) {
      throw const FormatException('Invalid release version');
    }
    return FlyVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3] ?? '0'),
      build ?? int.parse(match[4] ?? '0'),
    );
  }
  String get display => '$major.$minor.$patch${build == 0 ? '' : '+$build'}';
  @override
  int compareTo(FlyVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (build, other.build),
    ]) {
      final value = pair.$1.compareTo(pair.$2);
      if (value != 0) return value;
    }
    return 0;
  }
}

enum UpdatePlatform { windows, android }

class AppRelease {
  const AppRelease({
    required this.version,
    required this.downloadUri,
    required this.fileName,
    required this.size,
    required this.sha256,
  });
  final FlyVersion version;
  final Uri downloadUri;
  final String fileName, sha256;
  final int size;
}

class UpdateCheck {
  const UpdateCheck({this.latest, this.isNewer = false, this.supported = true});
  final AppRelease? latest;
  final bool isNewer, supported;
}

class UpdateService {
  UpdateService({
    Uri? baseUrl,
    String currentVersion = flyAppVersion,
    UpdatePlatform? platform,
    this.timeout = const Duration(seconds: 5),
  }) : baseUrl = baseUrl ?? FlyServiceEndpoints.updatesBaseUrl,
       currentVersion = FlyVersion.parse(currentVersion),
       platform =
           platform ??
           (Platform.isWindows
               ? UpdatePlatform.windows
               : Platform.isAndroid
               ? UpdatePlatform.android
               : null);
  final Uri baseUrl;
  final FlyVersion currentVersion;
  final UpdatePlatform? platform;
  final Duration timeout;

  Future<UpdateCheck> check() async {
    final target = platform;
    if (target == null) return const UpdateCheck(supported: false);
    // No installation code, account token, current version, or cookies are sent.
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = 'Fly';
    try {
      return await (() async {
        final request = await client.getUrl(
          FlyServiceEndpoints.endpoint(baseUrl, [
            'updates',
            'latest',
            target.name,
          ]),
        );
        request.followRedirects = false;
        final response = await request.close();
        if (response.statusCode != 200) {
          throw const HttpException('Update lookup failed');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 64 * 1024) {
            throw const FormatException('Release response too large');
          }
        }
        final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final raw = data['latest'];
        if (raw == null) return const UpdateCheck();
        final value = (raw as Map).cast<String, dynamic>();
        final path = value['downloadPath'] as String;
        final uri = baseUrl.resolve(path);
        final expectedPrefix = FlyServiceEndpoints.endpoint(baseUrl, [
          'updates',
          'download',
        ]).path;
        final fileName = value['fileName'] as String;
        if (uri.origin != baseUrl.origin ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment ||
            uri.pathSegments.length !=
                Uri.parse(expectedPrefix).pathSegments.length + 1 ||
            !uri.path.startsWith('$expectedPrefix/') ||
            uri.pathSegments.last != fileName ||
            !RegExp(
              r'^Fly-[A-Za-z0-9.+-]+\.(exe|apk)$',
              caseSensitive: false,
            ).hasMatch(fileName) ||
            !(fileName.toLowerCase().endsWith(
              target == UpdatePlatform.windows ? '.exe' : '.apk',
            ))) {
          throw const FormatException('Invalid release download location');
        }
        final hash = value['sha256'] as String;
        final size = value['size'] as int;
        final build = value['build'] as int;
        if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
            size < 1 ||
            build < 0) {
          throw const FormatException('Invalid release metadata');
        }
        final release = AppRelease(
          version: FlyVersion.parse(value['version'] as String, build: build),
          downloadUri: uri,
          fileName: fileName,
          size: size,
          sha256: hash,
        );
        return UpdateCheck(
          latest: release,
          isNewer: release.version.compareTo(currentVersion) > 0,
        );
      })().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }
}
