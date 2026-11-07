import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../l10n/service_error_copy.dart';
import '../../../shared/data/workspace_folder_repository.dart';
import 'file_providers.dart';

/// An empty result selects My files; null means the user cancelled.
Future<String?> showFileMoveDialog(
  BuildContext context, {
  required String fileName,
  required String? currentFolderId,
  Set<String?>? currentFolderIds,
  String? hint,
  String? movingFolderId,
}) => showDialog<String>(
  context: context,
  builder: (_) => _FileMoveDialog(
    fileName: fileName,
    currentFolderIds: currentFolderIds ?? {currentFolderId},
    hint: hint,
    movingFolderId: movingFolderId,
  ),
);

class _FileMoveDialog extends ConsumerStatefulWidget {
  const _FileMoveDialog({
    required this.fileName,
    required this.currentFolderIds,
    this.hint,
    this.movingFolderId,
  });

  final String fileName;
  final Set<String?> currentFolderIds;
  final String? hint;
  final String? movingFolderId;

  @override
  ConsumerState<_FileMoveDialog> createState() => _FileMoveDialogState();
}

class _FileMoveDialogState extends ConsumerState<_FileMoveDialog> {
  String? _folderId;

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(fileFoldersProvider);
    final items = folders.valueOrNull ?? <WorkspaceFolder>[];
    final byId = {for (final folder in items) folder.id: folder};
    final moving = byId[widget.movingFolderId];
    final excluded = widget.movingFolderId == null
        ? <String>{}
        : ref
              .read(fileFolderRepositoryProvider)
              .descendants(widget.movingFolderId!, items);
    final current = byId[_folderId];
    final valid = _folderId == null || current != null;
    final path = <String>[];
    final seen = <String>{};
    var ancestor = current;
    while (ancestor != null && seen.add(ancestor.id)) {
      path.insert(0, ancestor.name);
      ancestor = byId[ancestor.parentId];
    }
    final root = context.l10n.t('filesRoot');
    final destination = [root, ...path].join(' / ');
    final children = items
        .where((f) => f.parentId == _folderId && !excluded.contains(f.id))
        .toList();
    final canMove =
        folders.hasValue &&
        !folders.isLoading &&
        !folders.hasError &&
        valid &&
        (widget.movingFolderId == null || moving != null) &&
        !excluded.contains(_folderId) &&
        widget.currentFolderIds.any((id) => id != _folderId);

    return AlertDialog(
      key: const ValueKey('file-move-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        context.l10n.t(
          widget.movingFolderId == null
              ? 'filesMoveTitle'
              : 'filesMoveFolderTitle',
        ),
      ),
      content: SizedBox(
        width: 440,
        height: (MediaQuery.sizeOf(context).height * .4).clamp(140, 360),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (widget.hint != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.hint!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('file-move-root'),
                  tooltip: root,
                  onPressed: _folderId == null
                      ? null
                      : () => setState(() => _folderId = null),
                  icon: const Icon(Icons.home_outlined),
                ),
                if (_folderId != null)
                  IconButton(
                    tooltip: context.l10n.t('filesMoveUp'),
                    onPressed: () =>
                        setState(() => _folderId = current?.parentId),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                Expanded(
                  child: Text(
                    destination,
                    key: const ValueKey('file-move-path'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: folders.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(context.flyError(error)),
                      TextButton(
                        onPressed: () => ref.invalidate(fileFoldersProvider),
                        child: Text(context.l10n.t('filesMoveRetry')),
                      ),
                    ],
                  ),
                ),
                data: (_) => !valid
                    ? Center(
                        child: Text(context.l10n.t('filesMoveUnavailable')),
                      )
                    : children.isEmpty
                    ? Center(child: Text(context.l10n.t('filesMoveNoFolders')))
                    : ListView.builder(
                        itemCount: children.length,
                        itemBuilder: (_, index) {
                          final folder = children[index];
                          return ListTile(
                            key: ValueKey('file-move-folder-${folder.id}'),
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(
                              folder.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => setState(() => _folderId = folder.id),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.t('cancel')),
        ),
        FilledButton(
          key: const ValueKey('file-move-confirm'),
          onPressed: canMove
              ? () => Navigator.pop(context, _folderId ?? '')
              : null,
          child: Text(context.l10n.t('filesMoveHere')),
        ),
      ],
    );
  }
}
