import 'package:flutter/material.dart';

import '../../l10n/fly_localizations.dart';

import '../data/workspace_folder_repository.dart';

/// Shared tree interaction, not shared folder ownership or database tables.
class WorkspaceFolderTree extends StatefulWidget {
  const WorkspaceFolderTree({
    required this.folders,
    required this.selectedId,
    required this.onSelect,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    this.onReveal,
    this.onFileDrop,
    this.selectionColor,
    this.folderIconColor,
    super.key,
  });
  final List<WorkspaceFolder> folders;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String?> onCreate;
  final ValueChanged<WorkspaceFolder> onRename, onDelete;
  final ValueChanged<WorkspaceFolder>? onReveal;
  final void Function(String fileId, String folderId)? onFileDrop;
  final Color? selectionColor, folderIconColor;
  @override
  State<WorkspaceFolderTree> createState() => _WorkspaceFolderTreeState();
}

class _WorkspaceFolderTreeState extends State<WorkspaceFolderTree> {
  final expanded = <String>{};
  String? hovered;
  @override
  void didUpdateWidget(covariant WorkspaceFolderTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) {
      final parents = {for (final f in widget.folders) f.id: f.parentId};
      final seen = <String>{};
      var parent = parents[widget.selectedId];
      while (parent != null && seen.add(parent)) {
        expanded.add(parent);
        parent = parents[parent];
      }
    }
  }

  Future<void> menu(WorkspaceFolder folder, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'create',
          child: Text(context.l10n.t('folderNewChild')),
        ),
        PopupMenuItem(value: 'rename', child: Text(context.l10n.t('rename'))),
        if (widget.onReveal != null)
          PopupMenuItem(
            value: 'reveal',
            child: Text(context.l10n.t('folderReveal')),
          ),
        PopupMenuItem(value: 'delete', child: Text(context.l10n.t('delete'))),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'create':
        widget.onCreate(folder.id);
      case 'rename':
        widget.onRename(folder);
      case 'delete':
        widget.onDelete(folder);
      case 'reveal':
        widget.onReveal?.call(folder);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <String?, List<WorkspaceFolder>>{};
    for (final folder in widget.folders) {
      children.putIfAbsent(folder.parentId, () => []).add(folder);
    }
    final rows = <(WorkspaceFolder, int)>[];
    final seen = <String>{};
    void add(String? parent, int depth) {
      for (final folder in children[parent] ?? <WorkspaceFolder>[]) {
        if (!seen.add(folder.id)) continue;
        rows.add((folder, depth));
        if (expanded.contains(folder.id)) add(folder.id, depth + 1);
      }
    }

    add(null, 0);
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final (folder, depth) = rows[index];
        return DragTarget<String>(
          onWillAcceptWithDetails: (_) => widget.onFileDrop != null,
          onAcceptWithDetails: (value) =>
              widget.onFileDrop?.call(value.data, folder.id),
          builder: (context, candidates, rejected) => MouseRegion(
            onEnter: (_) => setState(() => hovered = folder.id),
            onExit: (_) => setState(() => hovered = null),
            child: GestureDetector(
              onSecondaryTapDown: (details) =>
                  menu(folder, details.globalPosition),
              child: Material(
                color: candidates.isNotEmpty || widget.selectedId == folder.id
                    ? widget.selectionColor ??
                          Theme.of(context).colorScheme.primary
                              .withValues(alpha: .1)
                    : Colors.transparent,
                child: Row(
                  children: [
                    SizedBox(width: (depth * 14.0).clamp(0, 84)),
                    SizedBox(
                      width: 30,
                      child: children.containsKey(folder.id)
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              tooltip: expanded.contains(folder.id)
                                  ? context.l10n.t('folderCollapse')
                                  : context.l10n.t('folderExpand'),
                              icon: Icon(
                                expanded.contains(folder.id)
                                    ? Icons.expand_more
                                    : Icons.chevron_right,
                                size: 18,
                              ),
                              onPressed: () => setState(
                                () => expanded.contains(folder.id)
                                    ? expanded.remove(folder.id)
                                    : expanded.add(folder.id),
                              ),
                            )
                          : null,
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => widget.onSelect(folder.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                size: 17,
                                color: widget.folderIconColor,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  folder.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (hovered == folder.id) ...[
                      SizedBox(
                        width: 25,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: context.l10n.t('folderNewChild'),
                          icon: const Icon(Icons.add, size: 16),
                          onPressed: () => widget.onCreate(folder.id),
                        ),
                      ),
                      SizedBox(
                        width: 25,
                        child: Builder(
                          builder: (context) => IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: context.l10n.t('folderMore'),
                            icon: const Icon(Icons.more_horiz, size: 16),
                            onPressed: () {
                              final box =
                                  context.findRenderObject() as RenderBox;
                              menu(folder, box.localToGlobal(Offset.zero));
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<String?> workspaceNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _WorkspaceNameDialog(title: title, initial: initial),
);

class _WorkspaceNameDialog extends StatefulWidget {
  const _WorkspaceNameDialog({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_WorkspaceNameDialog> createState() => _WorkspaceNameDialogState();
}

class _WorkspaceNameDialogState extends State<_WorkspaceNameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    if (controller.text.trim().isNotEmpty) {
      Navigator.pop(context, controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      autofocus: true,
      controller: controller,
      maxLength: 200,
      onSubmitted: (_) => submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.t('cancel')),
      ),
      FilledButton(onPressed: submit, child: Text(context.l10n.t('confirm'))),
    ],
  );
}
