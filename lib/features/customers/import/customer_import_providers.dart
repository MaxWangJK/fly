import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';

import '../../tasks/presentation/task_providers.dart';
import 'customer_import_service.dart';
import 'customer_template_export.dart';

final customerImportServiceProvider = Provider(
  (ref) => CustomerImportService(ref.watch(databaseProvider)),
);
final customerTemplateExporterProvider = Provider(
  (ref) => CustomerTemplateExporter(),
);
final customerImportFilePickerProvider = Provider<Future<XFile?> Function()>(
  (ref) =>
      () => openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Excel', extensions: ['xlsx']),
        ],
      ),
);
