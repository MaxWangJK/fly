import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/fly_localizations.dart';
import '../data/file_browser_query.dart';
import 'file_entry_content.dart';

class FilePreviewPane extends StatelessWidget {
  const FilePreviewPane({
    required this.entry,
    required this.path,
    required this.onClose,
    required this.onOpen,
    this.onCustomer,
    this.onOrder,
    super.key,
  });
  final FileBrowserEntry entry;
  final String path;
  final VoidCallback onClose, onOpen;
  final VoidCallback? onCustomer, onOrder;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final file = entry.file;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.t('filePreview'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: l.t('fileClosePreview'),
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (file.deletedAt == null && file.mimeType.startsWith('image/'))
            SizedBox(
              height: 200,
              child: InteractiveViewer(
                child: Image.file(
                  File(path),
                  key: ValueKey(path),
                  cacheWidth: 1200,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      Center(child: Text(l.t('fileImageUnavailable'))),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(24),
              child: Icon(
                file.mimeType == 'application/pdf'
                    ? Icons.picture_as_pdf_outlined
                    : file.mimeType.startsWith('video/')
                    ? Icons.movie_outlined
                    : Icons.insert_drive_file_outlined,
                size: 64,
              ),
            ),
          const SizedBox(height: 12),
          FutureBuilder<bool>(
            future: File(path).exists(),
            builder: (context, snapshot) => snapshot.data == false
                ? Text(
                    l.isZh ? '文件内容尚未下载。云同步只传文件信息，请通过电脑扫码进行本地文件同步。' : 'File not downloaded. Cloud sync transfers file information only. Pair with your desktop to transfer file contents locally.',
                  )
                : const SizedBox.shrink(),
          ),
          SelectableText(
            entry.name,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          Text(fileSizeLabel(file.fileSize)),
          Text(
            '${l.t('fileModified')}: ${DateFormat('yyyy-MM-dd HH:mm').format(file.updatedAt)}',
          ),
          if (entry.fileTags.isNotEmpty)
            Text('${l.t('fileOwnTags')}: ${entry.fileTags}'),
          if (entry.customerName.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.person_outline, size: 16),
                label: Text(entry.customerName),
                onPressed: onCustomer,
              ),
            ),
          if (entry.orderNumber.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.receipt_long_outlined, size: 16),
                label: Text(entry.orderNumber),
                onPressed: onOrder,
              ),
            ),
          const SizedBox(height: 12),
          if (file.deletedAt == null)
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new),
              label: Text(l.t('fileOpenSystem')),
            ),
        ],
      ),
    );
  }
}
