import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

enum TemplateExportResult { saved, shared, cancelled }

class CustomerTemplateExporter {
  Future<TemplateExportResult> save(
    Uint8List bytes, {
    required Rect shareOrigin,
  }) async {
    const name = 'Fly-Customer-Import-Template.xlsx';
    const mime =
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (Platform.isAndroid || Platform.isIOS) {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: mime)],
          fileNameOverrides: [name],
          sharePositionOrigin: shareOrigin,
        ),
      );
      return result.status == ShareResultStatus.dismissed
          ? TemplateExportResult.cancelled
          : TemplateExportResult.shared;
    }
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel', extensions: ['xlsx']),
      ],
    );
    if (location == null) return TemplateExportResult.cancelled;
    await File(location.path).writeAsBytes(bytes, flush: true);
    return TemplateExportResult.saved;
  }
}
