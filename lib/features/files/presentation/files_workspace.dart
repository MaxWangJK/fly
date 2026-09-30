import '../../../l10n/service_error_copy.dart';

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/settings/navigation_settings.dart';
import '../../../core/database/app_database.dart';
import '../../../l10n/fly_localizations.dart';
import '../../../shared/attachments/attachment_providers.dart';
import '../../../shared/data/workspace_folder_repository.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../../../shared/design_system/workspace_folder_tree.dart';
import '../../../shared/search/fuzzy_match.dart';
import '../../customers/presentation/customer_providers.dart';
import '../../orders/presentation/order_providers.dart';
import '../../tasks/presentation/task_providers.dart';
import '../data/file_browser_query.dart';
import '../data/managed_file_repository.dart';
import '../data/managed_file_storage.dart';
import '../data/platform_file_transfer.dart';
import 'file_providers.dart';
import 'file_entry_content.dart';
import 'file_preview_pane.dart';

class FilesWorkspace extends ConsumerStatefulWidget {
  const FilesWorkspace({this.initialFileId, super.key});
  final String? initialFileId;
  @override
  ConsumerState<FilesWorkspace> createState() => _FilesWorkspaceState();
}

class _FilesWorkspaceState extends ConsumerState<FilesWorkspace> {
  FileCollection collection = FileCollection.recent;
  FileSort sort = FileSort.modified;
  String? folderId, selectedId, cutId;
  String search = '';
  bool includeChildren = false, importing = false;
  FileViewMode viewMode = FileViewMode.small;
  double progress = 0;
  ImportCancellation? cancellation;
  final tags = <String>{};
  final customerTags = <String>{};
  Future<void> filters() async {
    final own = await ref.read(managedFileRepositoryProvider).watchTags().first;
    final db = ref.read(databaseProvider);
    final customers =
        await (db.select(db.tags)
              ..where((t) => t.scope.equals('customer'))
              ..where((t) => t.deletedAt.isNull())
              ..where((t) => t.isActive.equals(true)))
            .get();
    if (!mounted) return;
    final selectedFiles = {...tags};
    final selectedCustomers = {...customerTags};
    var term = '';
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(context.l10n.t('filesTagAnd')),
          content: SizedBox(
            width: 360,
            height: 420,
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: context.l10n.t('filesTagSearch'),
                  ),
                  onChanged: (v) => update(() => term = v.trim()),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      ListTile(
                        dense: true,
                        title: Text(context.l10n.t('fileOwnTags')),
                      ),
                      for (final tag in own.where(
                        (t) =>
                            term.isEmpty || FuzzyMatch.matches(term, [t.name]),
                      ))
                        CheckboxListTile(
                          dense: true,
                          title: Text(tag.name),
                          value: selectedFiles.contains(tag.id),
                          onChanged: (v) => update(() {
                            v == true
                                ? selectedFiles.add(tag.id)
                                : selectedFiles.remove(tag.id);
                          }),
                        ),
                      if (collection == FileCollection.customers) ...[
                        ListTile(
                          dense: true,
                          title: Text(context.l10n.t('filesCustomerTags')),
                        ),
                        for (final tag in customers.where(
                          (t) =>
                              term.isEmpty ||
                              FuzzyMatch.matches(term, [t.name]),
                        ))
                          CheckboxListTile(
                            dense: true,
                            title: Text(tag.name),
                            value: selectedCustomers.contains(tag.id),
                            onChanged: (v) => update(() {
                              v == true
                                  ? selectedCustomers.add(tag.id)
                                  : selectedCustomers.remove(tag.id);
                            }),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                selectedFiles.clear();
                selectedCustomers.clear();
                Navigator.pop(context, true);
              },
              child: Text(context.l10n.t('filesClear')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.t('filesApply')),
            ),
          ],
        ),
      ),
    );
    if (apply == true && mounted) {
      tags
        ..clear()
        ..addAll(selectedFiles);
      customerTags
        ..clear()
        ..addAll(selectedCustomers);
      reload();
    }
  }

  Stream<List<FileBrowserEntry>>? rows;
  bool? lastCrm;
  String? locateId;
  Future<void> copySelected() async {
    if (selectedId == null) return;
    final file = await ref
        .read(managedFileRepositoryProvider)
        .find(selectedId!);
    if (!mounted) return;
    if (file == null || file.deletedAt != null) {
      throw StateError(context.l10n.t('filesMissing'));
    }
    await PlatformFileTransfer().copy(
      ref.read(managedFileStorageProvider).absolute(file.relativePath),
    );
  }

  @override
  void initState() {
    super.initState();
    locateId = widget.initialFileId;
    selectedId = locateId;
  }

  void reload() {
    rows = null;
    if (mounted) setState(() {});
  }

  void select(FileCollection value, [String? folder]) {
    locateId = null;
    collection = value;
    folderId = folder;
    selectedId = null;
    reload();
  }

  Future<void> attempt(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.flyError(e))));
      }
    }
  }

  @override
  void dispose() {
    cancellation?.cancel();
    super.dispose();
  }

  Future<void> importPaths(List<String> paths) async {
    if (importing ||
        collection == FileCollection.deleted ||
        collection == FileCollection.customers) {
      return;
    }
    final destination = collection == FileCollection.folder ? folderId : null;
    final storage = ref.read(managedFileStorageProvider);
    final repo = ref.read(managedFileRepositoryProvider);
    cancellation = ImportCancellation();
    setState(() {
      importing = true;
      progress = 0;
    });
    try {
      for (final path in paths) {
        ImportedFile? copied;
        bool committed = false;
        try {
          copied = await storage.import(
            path,
            folderId: destination,
            cancellation: cancellation,
            progress: (done, total) {
              if (mounted) {
                setState(() => progress = total == 0 ? 1 : done / total);
              }
            },
          );
          cancellation!.check();
          String? id;
          try {
            id = await repo.commit(copied, folderId: destination);
          } on DuplicateManagedFile {
            if (!mounted) throw ImportCancelled();
            final choice = await showDialog<DuplicateFileAction>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(context.l10n.t('filesExists')),
                content: Text(
                  '${copied!.name}\n${context.l10n.t('filesExistsBody')}',
                ),
                actions: [
                  for (final option in DuplicateFileAction.values)
                    TextButton(
                      onPressed: () => Navigator.pop(context, option),
                      child: Text(switch (option) {
                        DuplicateFileAction.skip => context.l10n.t('filesSkip'),
                        DuplicateFileAction.keepCopy => context.l10n.t(
                          'filesKeepCopy',
                        ),
                        DuplicateFileAction.replace => context.l10n.t(
                          'filesReplace',
                        ),
                      }),
                    ),
                ],
              ),
            );
            cancellation!.check();
            id = await repo.commit(
              copied,
              folderId: destination,
              duplicateAction: choice ?? DuplicateFileAction.skip,
            );
          }
          committed = id != null;
          if (mounted) setState(() => selectedId = id);
        } finally {
          if (copied != null && !committed) await storage.discard(copied);
        }
      }
    } on ImportCancelled {
      /* Explicit cancellation; partial copy is removed. */
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> createFolder(String? parent) async {
    final name = await workspaceNameDialog(
      context,
      title: context.l10n.t('filesNewFolder'),
    );
    if (name != null) {
      await attempt(() async {
        final id = await ref
            .read(fileFolderRepositoryProvider)
            .create(name, parentId: parent);
        if (mounted) select(FileCollection.folder, id);
      });
    }
  }

  Future<void> folderDelete(WorkspaceFolder f) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.l10n.t('filesDeleteFolder')),
        content: Text('${f.name}\n${context.l10n.t('filesDeleteFolderBody')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(context.l10n.t('noteTrash')),
          ),
        ],
      ),
    );
    if (yes == true) {
      await attempt(() async {
        final failures = await ref.read(fileFolderActionsProvider).remove(f.id);
        if (failures > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.t('filesCacheWarning'))),
          );
        }
        if (mounted) select(FileCollection.recent);
      });
    }
  }

  Future<void> open(FileBrowserEntry entry) async {
    final latest = await ref
        .read(managedFileRepositoryProvider)
        .find(entry.file.id);
    if (!mounted) return;
    if (latest == null || latest.deletedAt != null) {
      throw StateError(context.l10n.t('filesRestoreFirst'));
    }
    await ref
        .read(attachmentOpenerProvider)
        .open(
          ref
              .read(managedFileStorageProvider)
              .absolute(entry.file.relativePath),
        );
    await ref.read(managedFileRepositoryProvider).opened(entry.file.id);
  }

  Future<void> revealFolder(WorkspaceFolder folder) async {
    final files = await ref
        .read(fileFolderActionsProvider)
        .directFiles(folder.id);
    if (!mounted) return;
    final selected = await showDialog<AttachmentRecord>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${folder.name} · ${context.l10n.t('filesDiskLocation')}'),
        content: SizedBox(
          width: 420,
          height: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.t('filesLogicalFolderHint')),
              const SizedBox(height: 12),
              Expanded(
                child: files.isEmpty
                    ? Center(child: Text(context.l10n.t('filesNoDirectFiles')))
                    : ListView.builder(
                        itemCount: files.length,
                        itemBuilder: (_, index) {
                          final file = files[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.insert_drive_file_outlined,
                            ),
                            title: Text(
                              file.displayName.isEmpty
                                  ? file.originalName
                                  : file.displayName,
                            ),
                            onTap: () => Navigator.pop(context, file),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.t('filesClose')),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      await ref
          .read(attachmentOpenerProvider)
          .reveal(
            ref
                .read(managedFileStorageProvider)
                .absolute(selected.relativePath),
          );
    }
  }

  Future<void> menu(FileBrowserEntry entry, Offset point) async {
    final f = entry.file;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(point.dx, point.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        if (f.deletedAt != null)
          PopupMenuItem(
            value: 'restore',
            child: Text(context.l10n.t('restore')),
          )
        else ...[
          PopupMenuItem(
            value: 'open',
            child: Text(context.l10n.t('filesOpen')),
          ),
          if (f.mimeType.startsWith('image/'))
            PopupMenuItem(
              value: 'preview',
              child: Text(context.l10n.t('filePreview')),
            ),
          PopupMenuItem(
            value: 'reveal',
            child: Text(context.l10n.t('filesReveal')),
          ),
          PopupMenuItem(value: 'rename', child: Text(context.l10n.t('rename'))),
          PopupMenuItem(
            value: 'tags',
            child: Text(context.l10n.t('fileOwnTags')),
          ),
          PopupMenuItem(
            value: 'path',
            child: Text(context.l10n.t('filesCopyPath')),
          ),
          if (Platform.isWindows)
            PopupMenuItem(
              value: 'copy',
              child: Text(context.l10n.t('filesCopy')),
            ),
          if (f.ownerType == 'library')
            PopupMenuItem(
              value: 'cut',
              child: Text(context.l10n.t('filesCut')),
            ),
          if (f.ownerType == 'library')
            PopupMenuItem(
              value: 'delete',
              child: Text(context.l10n.t('noteTrash')),
            ),
          if (f.ownerType == 'customer')
            PopupMenuItem(
              value: 'customer',
              child: Text(context.l10n.t('filesViewCustomer')),
            ),
        ],
        PopupMenuItem(value: 'info', child: Text(context.l10n.t('details'))),
      ],
    );
    if (!mounted || action == null) return;
    await attempt(() async {
      final repo = ref.read(managedFileRepositoryProvider);
      final path = ref
          .read(managedFileStorageProvider)
          .absolute(f.relativePath);
      switch (action) {
        case 'open':
          await open(entry);
        case 'reveal':
          await ref.read(attachmentOpenerProvider).reveal(path);
        case 'path':
          await Clipboard.setData(ClipboardData(text: path));
        case 'copy':
          await PlatformFileTransfer().copy(path);
        case 'cut':
          setState(() => cutId = f.id);
        case 'rename':
          final name = await workspaceNameDialog(
            context,
            title: context.l10n.t('rename'),
            initial: entry.name,
          );
          if (name != null) await repo.rename(f.id, name);
        case 'tags':
          await showDialog<void>(
            context: context,
            builder: (_) => _FileTagsDialog(fileId: f.id),
          );
        case 'delete':
          await repo.remove(f.id);
          await ref.read(thumbnailCacheProvider).remove(f);
        case 'restore':
          await repo.restore(f.id);
        case 'customer':
          ref.read(selectedCustomerIdProvider.notifier).state = f.ownerId;
          context.go('/customers/all');
        case 'preview':
          await showDialog<void>(
            context: context,
            builder: (c) => Dialog(
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: InteractiveViewer(
                      child: Image.file(
                        File(path),
                        errorBuilder: (_, _, _) =>
                            Text(context.l10n.t('fileImageUnavailable')),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: context.l10n.t('fileClosePreview'),
                      onPressed: () => Navigator.pop(c),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          );
        case 'info':
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(entry.name),
              content: SelectableText(
                '${f.mimeType}\n${f.fileSize} bytes\n${context.l10n.t('fileModified')}: ${f.updatedAt}\n${entry.customerName}\n$path',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: Text(context.l10n.t('filesClose')),
                ),
              ],
            ),
          );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final crm = ref.watch(navigationSettingsProvider).value.crmVisible;
    if (lastCrm != crm) {
      lastCrm = crm;
      rows = null;
      if (!crm && collection == FileCollection.customers) {
        collection = FileCollection.recent;
      }
    }
    final folders = ref.watch(fileFoldersProvider);
    rows ??= FileBrowserQuery(ref.read(databaseProvider)).watch(
      collection: collection,
      folderId: folderId,
      descendants: includeChildren,
      search: search,
      fileTags: tags,
      sort: sort,
      crmVisible: crm,
      fileId: locateId,
      customerTags: collection == FileCollection.customers
          ? customerTags
          : const {},
    );
    final tree = Material(
      color: context.flyColors.secondarySidebar,
      child: Column(
        children: [
          ListTile(title: Text(context.l10n.t('filesWorkspace'))),
          ListTile(
            dense: true,
            leading: const Icon(Icons.history),
            title: Text(context.l10n.t('noteRecent')),
            selected: collection == FileCollection.recent,
            onTap: () => select(FileCollection.recent),
          ),
          if (crm)
            ListTile(
              dense: true,
              leading: const Icon(Icons.people_outline),
              title: Text(context.l10n.t('filesCustomers')),
              selected: collection == FileCollection.customers,
              onTap: () => select(FileCollection.customers),
            ),
          ListTile(
            dense: true,
            title: Text(context.l10n.t('filesRoot')),
            selected: collection == FileCollection.folder && folderId == null,
            onTap: () => select(FileCollection.folder),
            trailing: IconButton(
              tooltip: context.l10n.t('filesNewFolder'),
              onPressed: () => createFolder(null),
              icon: const Icon(Icons.add),
            ),
          ),
          Expanded(
            child: folders.when(
              data: (items) => WorkspaceFolderTree(
                folders: items,
                selectedId: folderId,
                onSelect: (id) => select(FileCollection.folder, id),
                onCreate: createFolder,
                onRename: (f) async {
                  final name = await workspaceNameDialog(
                    context,
                    title: context.l10n.t('rename'),
                    initial: f.name,
                  );
                  if (name != null) {
                    await attempt(
                      () => ref
                          .read(fileFolderRepositoryProvider)
                          .rename(f.id, name),
                    );
                  }
                },
                onDelete: folderDelete,
                onReveal: (folder) => attempt(() => revealFolder(folder)),
                onFileDrop: (file, id) => attempt(
                  () => ref.read(managedFileRepositoryProvider).move(file, id),
                ),
              ),
              error: (e, _) => Text(
                '${context.l10n.t('filesFolderError')}: ${context.flyError(e)}',
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.delete_outline),
            title: Text(context.l10n.t('noteDeleted')),
            onTap: () => select(FileCollection.deleted),
          ),
        ],
      ),
    );
    final browser = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => select(FileCollection.folder),
                child: Text(context.l10n.t('filesRoot')),
              ),
              if (collection == FileCollection.folder)
                ..._breadcrumbs(folders.valueOrNull ?? []),
              if (collection != FileCollection.folder)
                Text(switch (collection) {
                  FileCollection.recent => context.l10n.t('noteRecent'),
                  FileCollection.customers => context.l10n.t('filesCustomers'),
                  FileCollection.deleted => context.l10n.t('noteDeleted'),
                  _ => '',
                }),
              PopupMenuButton<FileViewMode>(
                tooltip: context.l10n.t('fileViewMode'),
                initialValue: viewMode,
                onSelected: (value) => setState(() => viewMode = value),
                icon: Icon(
                  viewMode == FileViewMode.list
                      ? Icons.view_list_outlined
                      : Icons.grid_view,
                ),
                itemBuilder: (_) => [
                  for (final mode in FileViewMode.values)
                    CheckedPopupMenuItem(
                      value: mode,
                      checked: viewMode == mode,
                      child: Text(context.l10n.t('fileView_${mode.name}')),
                    ),
                ],
              ),
              TextButton.icon(
                onPressed: () => attempt(filters),
                icon: const Icon(Icons.filter_list, size: 18),
                label: Text(
                  '${context.l10n.t('filesTagFilter')}${tags.isEmpty && customerTags.isEmpty ? '' : ' (${tags.length + customerTags.length})'}',
                ),
              ),
              PopupMenuButton<FileSort>(
                tooltip: context.l10n.t('filesSort'),
                initialValue: sort,
                onSelected: (v) {
                  sort = v;
                  reload();
                },
                itemBuilder: (_) => [
                  for (final s in FileSort.values)
                    PopupMenuItem(
                      value: s,
                      child: Text(switch (s) {
                        FileSort.modified => context.l10n.t('fileModified'),
                        FileSort.created => context.l10n.t('filesCreated'),
                        FileSort.name => context.l10n.t('filesName'),
                        FileSort.type => context.l10n.t('filesType'),
                        FileSort.size => context.l10n.t('filesSize'),
                      }),
                    ),
                ],
              ),
              if (collection == FileCollection.folder ||
                  collection == FileCollection.recent)
                TextButton.icon(
                  onPressed: importing
                      ? null
                      : () => attempt(() async {
                          final files = await openFiles();
                          await importPaths(files.map((f) => f.path).toList());
                        }),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(context.l10n.t('filesImport')),
                ),
              if (cutId != null && collection == FileCollection.folder)
                TextButton(
                  onPressed: () => attempt(() async {
                    await ref
                        .read(managedFileRepositoryProvider)
                        .move(cutId!, folderId);
                    if (mounted) setState(() => cutId = null);
                  }),
                  child: Text(context.l10n.t('filesPaste')),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.l10n.t('filesSearch'),
            ),
            onChanged: (s) {
              search = s;
              reload();
            },
          ),
        ),
        if (collection == FileCollection.folder)
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(context.l10n.t('filesIncludeChildren')),
            value: includeChildren,
            onChanged: (v) {
              includeChildren = v == true;
              reload();
            },
          ),
        if (importing)
          Row(
            children: [
              Expanded(child: LinearProgressIndicator(value: progress)),
              TextButton(
                onPressed: () => cancellation?.cancel(),
                child: Text(context.l10n.t('filesCancelImport')),
              ),
            ],
          ),
        if (collection == FileCollection.deleted)
          StreamBuilder<List<WorkspaceFolder>>(
            stream: ref.read(fileFolderRepositoryProvider).watch(deleted: true),
            builder: (context, snapshot) => Wrap(
              children: [
                for (final f in snapshot.data ?? <WorkspaceFolder>[])
                  TextButton.icon(
                    onPressed: () => attempt(
                      () =>
                          ref.read(fileFolderRepositoryProvider).restore(f.id),
                    ),
                    icon: const Icon(Icons.restore, size: 16),
                    label: Text('${context.l10n.t('restore')} ${f.name}'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: DropTarget(
            onDragDone: (details) => attempt(
              () => importPaths(details.files.map((f) => f.path).toList()),
            ),
            child: StreamBuilder<List<FileBrowserEntry>>(
              stream: rows,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(context.l10n.t('filesLoadError')),
                        TextButton(
                          onPressed: reload,
                          child: Text(context.l10n.t('licenseRetryShort')),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snapshot.data!;
                if (entries.isEmpty) {
                  return Center(child: Text(context.l10n.t('filesEmpty')));
                }
                return fileResults(entries);
              },
            ),
          ),
        ),
      ],
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
            attempt(copySelected),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, c) => c.maxWidth < 650
              ? Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Builder(
                            builder: (context) => TextButton.icon(
                              onPressed: () => showModalBottomSheet<void>(
                                context: context,
                                builder: (_) =>
                                    SizedBox(height: 500, child: tree),
                              ),
                              icon: const Icon(Icons.folder_outlined),
                              label: Text(context.l10n.t('filesFolders')),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: browser),
                  ],
                )
              : Row(
                  children: [
                    SizedBox(width: 220, child: tree),
                    const VerticalDivider(width: 1),
                    Expanded(child: browser),
                  ],
                ),
        ),
      ),
    );
  }

  List<Widget> _breadcrumbs(List<WorkspaceFolder> folders) {
    final path = <WorkspaceFolder>[];
    final seen = <String>{};
    var id = folderId;
    while (id != null && seen.add(id)) {
      final f = folders.where((f) => f.id == id).firstOrNull;
      if (f == null) break;
      path.insert(0, f);
      id = f.parentId;
    }
    return [
      for (final f in path)
        TextButton(
          onPressed: () => select(FileCollection.folder, f.id),
          child: Text('› ${f.name}'),
        ),
    ];
  }

  Widget fileResults(List<FileBrowserEntry> entries) {
    final selected = entries
        .where((entry) => entry.file.id == selectedId)
        .firstOrNull;
    Widget listing = viewMode != FileViewMode.list
        ? GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: viewMode == FileViewMode.small ? 150 : 170,
              mainAxisExtent:
                  (viewMode == FileViewMode.small ? 118 : 156) +
                  (MediaQuery.textScalerOf(context).scale(26) - 26),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: entries.length,
            itemBuilder: (_, i) => tile(entries[i]),
          )
        : LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: constraints.maxWidth.clamp(800, double.infinity),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  itemBuilder: (_, i) => tile(entries[i]),
                ),
              ),
            ),
          );
    if (selected == null) return listing;
    final preview = FilePreviewPane(
      key: ValueKey('file-preview-${selected.file.id}'),
      entry: selected,
      path: ref
          .read(managedFileStorageProvider)
          .absolute(selected.file.relativePath),
      onClose: () => setState(() => selectedId = null),
      onOpen: () => attempt(() => open(selected)),
      onCustomer: selected.customerId == null
          ? null
          : () {
              ref.read(selectedCustomerIdProvider.notifier).state =
                  selected.customerId;
              context.go('/customers/all');
            },
      onOrder: selected.orderId == null
          ? null
          : () {
              ref.read(orderCustomerFilterProvider.notifier).state = null;
              ref.read(selectedOrderIdProvider.notifier).state =
                  selected.orderId;
              context.go('/orders/all');
            },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 800) {
          return Row(
            children: [
              Expanded(child: listing),
              const VerticalDivider(width: 1),
              SizedBox(width: 280, child: preview),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: listing),
            const Divider(height: 1),
            SizedBox(
              height: (constraints.maxHeight * .45).clamp(0, 260),
              child: preview,
            ),
          ],
        );
      },
    );
  }

  Widget tile(FileBrowserEntry entry) {
    final f = entry.file;
    final icon = Icon(
      f.mimeType.startsWith('image/')
          ? Icons.image_outlined
          : f.mimeType.startsWith('video/')
          ? Icons.movie_outlined
          : f.mimeType == 'application/pdf'
          ? Icons.picture_as_pdf_outlined
          : Icons.insert_drive_file_outlined,
      size: switch (viewMode) {
        FileViewMode.small => 36,
        FileViewMode.medium => 72,
        FileViewMode.list => 24,
      },
    );
    Widget visual = icon;
    if (f.deletedAt == null && f.mimeType.startsWith('image/')) {
      visual = FutureBuilder<File?>(
        future: ref.read(thumbnailCacheProvider).get(f),
        builder: (context, snapshot) => snapshot.data == null
            ? icon
            : Image.file(
                snapshot.data!,
                cacheWidth: 240,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => icon,
              ),
      );
    }
    final content = FileEntryContent(
      entry: entry,
      mode: viewMode,
      visual: visual,
      onCustomer: entry.customerId == null
          ? null
          : () {
              ref.read(selectedCustomerIdProvider.notifier).state =
                  entry.customerId;
              context.go('/customers/all');
            },
      onOrder: entry.orderId == null
          ? null
          : () {
              ref.read(orderCustomerFilterProvider.notifier).state = null;
              ref.read(selectedOrderIdProvider.notifier).state = entry.orderId;
              context.go('/orders/all');
            },
    );
    final card = Material(
      color: selectedId == f.id
          ? context.flyColors.selected
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => setState(() => selectedId = f.id),
        onDoubleTap: f.deletedAt == null
            ? () => attempt(() => open(entry))
            : null,
        onSecondaryTapUp: (d) => menu(entry, d.globalPosition),
        child: Padding(
          padding: EdgeInsets.all(viewMode == FileViewMode.list ? 0 : 8),
          child: Stack(
            children: [
              content,
              if (Platform.isWindows && f.deletedAt == null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onPanStart: (_) => attempt(
                      () => PlatformFileTransfer()
                          .drag(
                            ref
                                .read(managedFileStorageProvider)
                                .absolute(f.relativePath),
                          )
                          .then((_) {}),
                    ),
                    child: Tooltip(
                      message: context.l10n.t('filesDragOut'),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.open_in_new, size: 16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final transferable = Platform.isWindows && f.deletedAt == null
        ? GestureDetector(
            onPanStart: (_) => attempt(
              () => PlatformFileTransfer()
                  .drag(
                    ref
                        .read(managedFileStorageProvider)
                        .absolute(f.relativePath),
                  )
                  .then((_) {}),
            ),
            child: card,
          )
        : card;
    return f.ownerType == 'library' && f.deletedAt == null
        ? LongPressDraggable<String>(
            data: f.id,
            feedback: Material(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(entry.name),
              ),
            ),
            child: transferable,
          )
        : transferable;
  }
}

class _FileTagsDialog extends ConsumerStatefulWidget {
  const _FileTagsDialog({required this.fileId});
  final String fileId;
  @override
  ConsumerState<_FileTagsDialog> createState() => _FileTagsDialogState();
}

class _FileTagsDialogState extends ConsumerState<_FileTagsDialog> {
  String search = '';
  String get fileId => widget.fileId;
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(managedFileRepositoryProvider);
    return AlertDialog(
      title: Text(context.l10n.t('fileOwnTags')),
      content: SizedBox(
        width: 360,
        height: 360,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: context.l10n.t('filesTagCreate'),
              ),
              onChanged: (v) => setState(() => search = v.trim()),
              onSubmitted: (name) async {
                try {
                  final id = await repo.createTag(name);
                  await repo.setTag(fileId, id, true);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.flyError(e))),
                    );
                  }
                }
              },
            ),
            Expanded(
              child: StreamBuilder<List<FileTagLink>>(
                stream: repo.watchLinks(),
                builder: (context, links) => ref
                    .watch(libraryTagsProvider)
                    .when(
                      data: (tags) => ListView(
                        children: [
                          for (final tag in tags.where(
                            (t) =>
                                search.isEmpty ||
                                FuzzyMatch.matches(search, [t.name]),
                          ))
                            CheckboxListTile(
                              title: Text(tag.name),
                              value:
                                  links.data?.any(
                                    (l) =>
                                        l.fileId == fileId && l.tagId == tag.id,
                                  ) ??
                                  false,
                              onChanged: (value) =>
                                  repo.setTag(fileId, tag.id, value == true),
                            ),
                        ],
                      ),
                      error: (e, _) => Text(context.flyError(e)),
                      loading: () => const CircularProgressIndicator(),
                    ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.t('filesDone')),
        ),
      ],
    );
  }
}
