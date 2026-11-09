import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service.dart';

final updateControllerProvider = ChangeNotifierProvider<UpdateController>(
  (ref) => UpdateController(
    service: UpdateService(),
    launchDownload: (uri) =>
        launchUrl(uri, mode: LaunchMode.externalApplication),
  ),
);

class UpdateController extends ChangeNotifier {
  UpdateController({required this.service, required this.launchDownload});
  final UpdateService service;
  final Future<bool> Function(Uri) launchDownload;
  UpdateCheck? result;
  bool checking = false, openingDownload = false;
  bool checkFailed = false, downloadFailed = false;
  bool _disposed = false;
  String? _dismissedVersion;
  bool get showNotice =>
      result?.isNewer == true &&
      result?.latest?.version.display != _dismissedVersion;

  Future<void> check({bool silent = false}) async {
    if (checking || _disposed) return;
    checking = true;
    checkFailed = false;
    notifyListeners();
    try {
      final checked = await service.check();
      if (!_disposed) result = checked;
    } on Object {
      if (!_disposed && !silent) checkFailed = true;
    } finally {
      if (!_disposed) {
        checking = false;
        notifyListeners();
      }
    }
  }

  void dismiss() {
    _dismissedVersion = result?.latest?.version.display;
    notifyListeners();
  }

  Future<void> download() async {
    final release = result?.latest;
    if (release == null || openingDownload || _disposed) return;
    openingDownload = true;
    downloadFailed = false;
    notifyListeners();
    try {
      final opened = await launchDownload(release.downloadUri);
      if (!_disposed) downloadFailed = !opened;
    } on Object {
      if (!_disposed) downloadFailed = true;
    } finally {
      if (!_disposed) {
        openingDownload = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
