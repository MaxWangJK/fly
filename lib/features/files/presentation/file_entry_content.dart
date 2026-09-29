import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../data/file_browser_query.dart';

enum FileViewMode { small, medium, list }

String fileSizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// Layout only. Opening, selection and native file transfer remain in the workspace.
class FileEntryContent extends StatelessWidget {
  const FileEntryContent({
    required this.entry,
    required this.mode,
    required this.visual,
    this.onCustomer,
    this.onOrder,
    super.key,
  });
  final FileBrowserEntry entry;
  final FileViewMode mode;
  final Widget visual;
  final VoidCallback? onCustomer, onOrder;

  @override
  Widget build(BuildContext context) {
    final caption = entry.fileTags;
    Widget relation(String name, VoidCallback? action) => Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Tooltip(
        message: name,
        child: InkWell(
          onTap: action,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 95),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .08),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ),
    );
    final relations = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (entry.customerName.isNotEmpty)
          Flexible(child: relation(entry.customerName, onCustomer)),
        if (entry.orderNumber.isNotEmpty)
          Flexible(child: relation(entry.orderNumber, onOrder)),
      ],
    );
    final nameStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontSize: 13);
    final metadata = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontSize: 12);
    Widget label(String value, {bool name = false}) => Tooltip(
      message: value,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: name ? nameStyle : metadata,
      ),
    );
    if (mode == FileViewMode.list) {
      return SizedBox(
        key: ValueKey('file-list-row-${entry.file.id}'),
        height: (38 * MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
          38,
          100,
        ),
        child: Row(
          children: [
            SizedBox(width: 28, height: 28, child: visual),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: label(entry.name, name: true)),
            const SizedBox(width: 12),
            SizedBox(
              width: 65,
              child: label(
                p.extension(entry.name).replaceFirst('.', '').toUpperCase(),
              ),
            ),
            SizedBox(
              width: 140,
              child: label(
                DateFormat('yyyy-MM-dd HH:mm').format(entry.file.updatedAt),
              ),
            ),
            SizedBox(
              width: 85,
              child: label(fileSizeLabel(entry.file.fileSize)),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  if (caption.isNotEmpty) Expanded(child: label(caption)),
                  Flexible(child: relations),
                ],
              ),
            ),
            const SizedBox(width: 32),
          ],
        ),
      );
    }
    final size = mode == FileViewMode.small ? 36.0 : 72.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: size, height: size, child: visual),
        const SizedBox(height: 6),
        label(entry.name, name: true),
        if (caption.isNotEmpty) label(caption),
        if (entry.customerName.isNotEmpty || entry.orderNumber.isNotEmpty)
          relations,
      ],
    );
  }
}
