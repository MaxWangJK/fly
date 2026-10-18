import '../../../l10n/service_error_copy.dart';

import 'dart:io';
import 'dart:async';

import 'package:share_plus/share_plus.dart';

import '../data/permanent_file_deletion.dart';
import '../data/file_batch_actions.dart';
import '../data/file_browser_preferences.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

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
import '../../../shared/design_system/responsive_layout.dart';
import '../../../shared/design_system/mobile_workspace_actions.dart';
import '../../../app/shell/mobile_details.dart';
import 'image_file_viewer.dart';
import 'mobile_file_browser.dart';

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
  FileViewMode viewMode = FileViewMode.list;
  bool _viewInitialized = false;
  bool imagesFirst = true;
  bool _preferencesLoaded = false, _selecting = false, _batchBusy = false;
  bool _mobileHome = true, _showCustomerFolder = true;
  int _batchDone = 0, _batchTotal = 0;
  final _selectedFiles = <String>{};
  late FileBrowserPreferencesStore _preferences;
  double progress = 0;
  ImportCancellation? cancellation;
  final tags = <String>{};
  final customerTags = <String>{};
  final _imagePicker = ImagePicker();
  bool _cameraRecoveryStarted = false;

  Future<void> _addOnPhone() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: Text(context.l10n.t('filesImport')),
            onTap: () => Navigator.pop(sheet, 'import'),
          ),
          ListTile(
            key: const ValueKey('file-take-photo'),
            leading: const Icon(Icons.camera_alt_outlined),
            title: Text(context.l10n.isZh ? '拍照上传' : 'Take photo'),
            onTap: () => Navigator.pop(sheet, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: Text(context.l10n.t('filesNewFolder')),
            onTap: () => Navigator.pop(sheet, 'folder'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'camera') {
      await attempt(takePhoto);
    }
    if (action == 'folder') {
      await createFolder(
        folderId,
        customerCollection: collection == FileCollection.customers,
      );
    }
    if (action == 'import') {
      await attempt(() async {
        await importPicked(await openFiles());
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_viewInitialized) {
      _viewInitialized = true;
      if (isPhoneLayout(context)) {
        viewMode = FileViewMode.small;
        if (locateId == null) collection = FileCollection.folder;
      }
      _preferences = FileBrowserPreferencesStore(
        ref.read(databaseProvider),
        phone: isPhoneLayout(context),
      );
      unawaited(_restorePreferences());
    }
    if (!_cameraRecoveryStarted && Platform.isAndroid) {
      _cameraRecoveryStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          attempt(() async {
            final lost = await _imagePicker.retrieveLostData();
            if (!mounted) return;
            if (lost.exception != null) throw lost.exception!;
            if (lost.files != null) {
              await importPicked(lost.files!);
            }
          });
        }
      });
    }
  }

  Future<void> _restorePreferences() async {
    try {
      final saved = await _preferences.load();
      if (!mounted) return;
      viewMode = FileViewMode.values.firstWhere((v) => v.name == saved.view);
      sort = saved.sort;
      final phone = isPhoneLayout(context);
      if (locateId == null && !phone) {
        collection = saved.collection;
        folderId = saved.folderId;
      }
      imagesFirst = saved.imagesFirst;
      includeChildren = saved.includeChildren;
      _showCustomerFolder = saved.showCustomerFolder;
      if (!phone) {
        tags.addAll(saved.fileTags);
        customerTags.addAll(saved.customerTags);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('显示设置读取失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _preferencesLoaded = true;
          rows = null;
        });
      }
    }
  }

  void _savePreferences() {
    final value = FileBrowserPreferences(
      view: viewMode.name,
      collection: collection,
      folderId: folderId,
      sort: sort,
      imagesFirst: imagesFirst,
      includeChildren: includeChildren,
      fileTags: {...tags},
      customerTags: {...customerTags},
      showCustomerFolder: _showCustomerFolder,
    );
    unawaited(attempt(() => _preferences.save(value)));
  }

  void _toggleSelection(String id) => setState(() {
    _selectedFiles.contains(id)
        ? _selectedFiles.remove(id)
        : _selectedFiles.add(id);
  });

  FileBatchActions get _batchActions => FileBatchActions(
    ref.read(databaseProvider),
    ref.read(managedFileStorageProvider),
  );
  void _batchProgress(int done, int total) {
    if (mounted) {
      setState(() {
        _batchDone = done;
        _batchTotal = total;
      });
    }
  }

  Future<void> _shareFiles(Set<String> ids) async {
    if (_batchBusy) return;
    setState(() {
      _batchBusy = true;
      _batchDone = 0;
      _batchTotal = ids.length;
    });
    PreparedFileShare? prepared;
    var retainForReceiver = false;
    try {
      prepared = await _batchActions.prepareShare(
        ids,
        progress: _batchProgress,
      );
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox;
      final result = await SharePlus.instance.share(
        ShareParams(
          title: context.l10n.isZh ? '分享文件' : 'Share files',
          files: prepared.files
              .map((f) => XFile(f.path, mimeType: f.mimeType))
              .toList(),
          fileNameOverrides: prepared.files.map((f) => f.name).toList(),
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      // Windows returns before the receiver has read its StorageItems.
      // Platforms without completion callbacks retain copies for later cleanup.
      retainForReceiver = result.status == ShareResultStatus.unavailable;
    } finally {
      try {
        if (!retainForReceiver) await prepared?.cleanup();
      } finally {
        if (mounted) setState(() => _batchBusy = false);
      }
    }
  }

  Future<void> _deleteFiles(List<FileBrowserEntry> files) async {
    if (_batchBusy || files.isEmpty) return;
    final permanent = collection == FileCollection.deleted;
    final business = files.where((f) => f.file.ownerType != 'library').length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          permanent ? '永久删除 ${files.length} 项？' : '删除 ${files.length} 项？',
        ),
        content: Text(
          permanent
              ? '这些文件的实际内容将清理，无法恢复。删除会同步到其他设备。'
              : '文件将移入最近删除。${business > 0 ? '\n其中 $business 项关联附件也会从所属记录中移除。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('files-confirm-batch-delete'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(permanent ? '永久删除' : '删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _batchBusy = true;
      _batchDone = 0;
      _batchTotal = files.length;
    });
    try {
      final result = await _batchActions.delete(
        files.map((f) => f.file.id).toSet(),
        permanent: permanent,
        progress: _batchProgress,
      );
      if (!mounted) return;
      setState(() {
        _selectedFiles.removeAll(result.completed);
        if (_selectedFiles.isEmpty) _selecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errors.isEmpty
                ? '已${permanent ? '永久删除' : '删除'} ${result.completed.length} 项'
                : '已删除 ${result.completed.length} 项，${result.errors.length} 项失败：${result.errors.values.first}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<void> takePhoto() async {
    final zh = context.l10n.isZh;
    try {
      final photo = await _imagePicker.pickImage(source: ImageSource.camera);
      if (photo != null && mounted) await importPicked([photo]);
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied' ||
          e.code == 'camera_access_restricted') {
        throw StateError(
          zh
              ? '请在系统设置中允许 Fly 使用相机后重试'
              : 'Allow camera access in system settings and try again.',
        );
      }
      rethrow;
    }
  }

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
      _selectedFiles.clear();
      _savePreferences();
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
    _mobileHome = locateId == null;
    selectedId = locateId;
  }

  void reload() {
    rows = null;
    if (mounted) setState(() {});
  }

  void select(FileCollection value, [String? folder]) {
    if (isPhoneLayout(context)) {
      _mobileHome = false;
      search = '';
      FocusManager.instance.primaryFocus?.unfocus();
    }
    locateId = null;
    collection = value;
    folderId = folder;
    selectedId = null;
    _selectedFiles.clear();
    _selecting = false;
    reload();
    _savePreferences();
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

  Future<void> importPicked(List<XFile> files) =>
      importPaths(files.map((f) => f.path).toList(), pickedFiles: files);

  Future<String> _customerFilesDestination() => ref
      .read(fileFolderRepositoryProvider)
      .ensureCustomerFilesRoot(context.l10n.t('filesCustomers'));

  Future<void> importPaths(
    List<String> paths, {
    List<XFile>? pickedFiles,
  }) async {
    if (paths.isEmpty || importing || collection == FileCollection.deleted) {
      return;
    }
    final customerCollection = collection == FileCollection.customers;
    final currentFolder = collection == FileCollection.folder ? folderId : null;
    final storage = ref.read(managedFileStorageProvider);
    final repo = ref.read(managedFileRepositoryProvider);
    cancellation = ImportCancellation();
    setState(() {
      importing = true;
      progress = 0;
    });
    try {
      final destination = customerCollection
          ? await _customerFilesDestination()
          : currentFolder;
      cancellation!.check();
      if (!mounted) throw ImportCancelled();
      for (final (index, path) in paths.indexed) {
        ImportedFile? copied;
        bool committed = false;
        try {
          copied = await storage.import(
            path,
            pickedFile: pickedFiles?[index],
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

  Future<void> createFolder(
    String? parent, {
    bool customerCollection = false,
  }) async {
    final name = await workspaceNameDialog(
      context,
      title: context.l10n.t('filesNewFolder'),
    );
    if (name != null && mounted) {
      await attempt(() async {
        final destination = customerCollection
            ? await _customerFilesDestination()
            : parent;
        final id = await ref
            .read(fileFolderRepositoryProvider)
            .create(name, parentId: destination);
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
        if (mounted) {
          if (isPhoneLayout(context)) {
            _phoneHome();
          } else {
            select(FileCollection.recent);
          }
        }
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
    if (latest.mimeType.startsWith('image/')) {
      final path = ref
          .read(managedFileStorageProvider)
          .absolute(latest.relativePath);
      if (!await File(path).exists()) throw StateError('文件内容尚未下载，请检查同步状态');
      await ref.read(managedFileRepositoryProvider).opened(entry.file.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => ImageFileViewer(path: path, name: latest.originalName),
      );
      return;
    }
    await ref
        .read(attachmentOpenerProvider)
        .open(
          ref.read(managedFileStorageProvider).absolute(latest.relativePath),
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
    final action = isPhoneLayout(context)
        ? await showModalBottomSheet<String>(
            context: context,
            useRootNavigator: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (sheet) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      entry.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final action
                      in f.deletedAt != null
                          ? [
                              if (f.ownerType == 'library') ("restore", "恢复"),
                              ("purge", "永久删除"),
                            ]
                          : [
                              ("info", "详情"),
                              ("rename", "重命名"),
                              ("share", "分享"),
                              ("select", "选择"),
                              ("delete", "删除"),
                            ])
                    ListTile(
                      title: Text(action.$2),
                      onTap: () => Navigator.pop(sheet, action.$1),
                    ),
                ],
              ),
            ),
          )
        : await showMenu<String>(
            context: context,
            position: RelativeRect.fromRect(
              Rect.fromLTWH(point.dx, point.dy, 0, 0),
              Offset.zero & overlay.size,
            ),
            items: [
              if (f.deletedAt != null && f.ownerType == 'library')
                PopupMenuItem(
                  value: 'restore',
                  child: Text(context.l10n.t('restore')),
                ),
              if (f.deletedAt != null)
                const PopupMenuItem(value: 'purge', child: Text('永久删除'))
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
                if (!isPhoneLayout(context))
                  PopupMenuItem(
                    value: 'reveal',
                    child: Text(context.l10n.t('filesReveal')),
                  ),
                PopupMenuItem(
                  value: 'rename',
                  child: Text(context.l10n.t('rename')),
                ),
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
              PopupMenuItem(
                value: 'info',
                child: Text(context.l10n.t('details')),
              ),
            ],
          );
    if (!mounted || action == null) return;
    await attempt(() async {
      final repo = ref.read(managedFileRepositoryProvider);
      final path = ref
          .read(managedFileStorageProvider)
          .absolute(f.relativePath);
      switch (action) {
        case 'share':
          await _shareFiles({f.id});
        case 'select':
          setState(() {
            _selecting = true;
            _selectedFiles.add(f.id);
          });
        case 'purge':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: const Text('永久删除文件？'),
              content: Text('“${entry.name}”的文件内容将被清理，无法恢复。删除会同步到其他设备。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('永久删除'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await PermanentFileDeletion(
              ref.read(databaseProvider),
              ref.read(managedFileStorageProvider),
            ).purge(f.id);
          }
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
          if (f.ownerType != 'library') {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialog) => AlertDialog(
                title: const Text('删除关联附件？'),
                content: Text('“${entry.name}”也会从所属客户、订单或笔记中移除。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('删除'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
          }
          if (!mounted) return;
          await repo.remove(
            f.id,
            allowBusinessAttachment: isPhoneLayout(context),
          );
          await ref.read(thumbnailCacheProvider).remove(f);
        case 'restore':
          await repo.restore(f.id);
        case 'customer':
          ref.read(selectedCustomerIdProvider.notifier).state = f.ownerId;
          context.go('/customers/all');
        case 'preview':
          await open(entry);
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
    if (!_preferencesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final clarityStyle = ref.watch(flyPaletteProvider) == FlyPaletteId.clarity;
    final crm = ref.watch(navigationSettingsProvider).value.crmVisible;
    if (lastCrm != crm) {
      lastCrm = crm;
      rows = null;
      if (!crm && collection == FileCollection.customers) {
        collection = FileCollection.recent;
      }
    }
    final folders = ref.watch(fileFoldersProvider);
    final phone = isPhoneLayout(context);
    final homeSearch = phone && _mobileHome && search.trim().isNotEmpty;
    rows ??= FileBrowserQuery(ref.read(databaseProvider)).watch(
      collection: homeSearch ? FileCollection.recent : collection,
      folderId: folderId,
      descendants: phone ? search.trim().isNotEmpty : includeChildren,
      search: search,
      fileTags: !phone && locateId == null ? tags : const {},
      sort: sort,
      crmVisible: crm && (!phone || _showCustomerFolder),
      fileId: locateId,
      customerTags: !phone && collection == FileCollection.customers
          ? customerTags
          : const {},
    );
    if (phone) return _phoneBrowser(folders, crm);
    final tree = Material(
      color: context.flyColors.secondarySidebar,
      child: ListTileTheme(
        data: ListTileThemeData(
          selectedTileColor: clarityStyle ? null : context.flyColors.selected,
          selectedColor: clarityStyle ? null : context.flyColors.accent,
          shape: clarityStyle
              ? null
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
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
                  selectionColor: clarityStyle
                      ? null
                      : context.flyColors.selected,
                  folderIconColor: clarityStyle
                      ? null
                      : context.flyColors.accent,
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
                    () =>
                        ref.read(managedFileRepositoryProvider).move(file, id),
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
              selected: !clarityStyle && collection == FileCollection.deleted,
              onTap: () => select(FileCollection.deleted),
            ),
          ],
        ),
      ),
    );
    final browser = ColoredBox(
      key: const ValueKey('file-browser-background'),
      color: context.flyColors.surface,
      child: Column(
        children: [
          ColoredBox(
            color: context.flyColors.surface,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    key: const ValueKey('files-multi-select'),
                    tooltip: _selecting ? '退出多选' : '多选',
                    onPressed: _batchBusy
                        ? null
                        : () => setState(() {
                            _selecting = !_selecting;
                            _selectedFiles.clear();
                          }),
                    icon: Icon(_selecting ? Icons.close : Icons.checklist),
                  ),
                  if (isPhoneLayout(context))
                    IconButton(
                      tooltip: context.l10n.t('filesFolders'),
                      icon: const Icon(Icons.folder_outlined),
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        useSafeArea: true,
                        builder: (_) => SizedBox(
                          height: MediaQuery.sizeOf(context).height * .7,
                          child: tree,
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: () => select(FileCollection.folder),
                    child: Text(context.l10n.t('filesRoot')),
                  ),
                  if (collection == FileCollection.folder)
                    ..._breadcrumbs(folders.valueOrNull ?? []),
                  if (collection != FileCollection.folder)
                    Text(switch (collection) {
                      FileCollection.recent => context.l10n.t('noteRecent'),
                      FileCollection.customers => context.l10n.t(
                        'filesCustomers',
                      ),
                      FileCollection.deleted => context.l10n.t('noteDeleted'),
                      _ => '',
                    }),
                  PopupMenuButton<FileViewMode>(
                    key: const ValueKey('file-view-mode'),
                    tooltip: context.l10n.t('fileViewMode'),
                    initialValue: viewMode,
                    onSelected: (value) {
                      setState(() => viewMode = value);
                      _savePreferences();
                    },
                    icon: Icon(
                      viewMode == FileViewMode.list
                          ? Icons.view_list_outlined
                          : Icons.grid_view,
                    ),
                    itemBuilder: (_) => [
                      for (final mode
                          in isPhoneLayout(context)
                              ? [FileViewMode.small, FileViewMode.list]
                              : FileViewMode.values)
                        CheckedPopupMenuItem(
                          value: mode,
                          checked: viewMode == mode,
                          child: Text(
                            isPhoneLayout(context) && mode == FileViewMode.small
                                ? '相册'
                                : context.l10n.t('fileView_${mode.name}'),
                          ),
                        ),
                    ],
                  ),
                  if (isPhoneLayout(context))
                    PopupMenuButton<bool>(
                      key: const ValueKey('file-kind-order'),
                      tooltip: '图片和文件顺序',
                      icon: const Icon(Icons.swap_vert),
                      onSelected: (v) {
                        setState(() => imagesFirst = v);
                        _savePreferences();
                      },
                      itemBuilder: (_) => [
                        for (final value in [true, false])
                          CheckedPopupMenuItem(
                            value: value,
                            checked: imagesFirst == value,
                            child: Text(value ? '图片在前' : '文件在前'),
                          ),
                      ],
                    ),
                  TextButton.icon(
                    onPressed: () => attempt(filters),
                    icon: const Icon(Icons.filter_list, size: 18),
                    label: Text(
                      '${context.l10n.t('filesTagFilter')}${tags.isEmpty && (collection != FileCollection.customers || customerTags.isEmpty) ? '' : ' (${tags.length + (collection == FileCollection.customers ? customerTags.length : 0)})'}',
                    ),
                  ),
                  PopupMenuButton<FileSort>(
                    tooltip: context.l10n.t('filesSort'),
                    initialValue: sort,
                    onSelected: (v) {
                      sort = v;
                      reload();
                      _savePreferences();
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
                  if (!isPhoneLayout(context) &&
                      (collection == FileCollection.folder ||
                          collection == FileCollection.recent))
                    TextButton.icon(
                      onPressed: importing
                          ? null
                          : () => attempt(() async {
                              final files = await openFiles();
                              await importPicked(files);
                            }),
                      icon: const Icon(Icons.file_upload_outlined),
                      label: Text(context.l10n.t('filesImport')),
                    ),
                  if (!isPhoneLayout(context) &&
                      (Platform.isAndroid || Platform.isIOS) &&
                      (collection == FileCollection.folder ||
                          collection == FileCollection.recent))
                    TextButton.icon(
                      key: const ValueKey('file-take-photo'),
                      onPressed: importing ? null : () => attempt(takePhoto),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(context.l10n.isZh ? '拍照上传' : 'Take photo'),
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
          ),
          if (!isPhoneLayout(context))
            ColoredBox(
              color: context.flyColors.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: context.l10n.t('filesSearch'),
                  ),
                  onChanged: (s) {
                    search = s;
                    _selectedFiles.clear();
                    reload();
                  },
                ),
              ),
            ),
          if (collection == FileCollection.folder)
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(context.l10n.t('filesIncludeChildren')),
                value: includeChildren,
                onChanged: (v) {
                  includeChildren = v == true;
                  reload();
                  _selectedFiles.clear();
                  _savePreferences();
                },
              ),
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
              stream: ref
                  .read(fileFolderRepositoryProvider)
                  .watch(deleted: true),
              builder: (context, snapshot) => Wrap(
                children: [
                  for (final f in snapshot.data ?? <WorkspaceFolder>[])
                    TextButton.icon(
                      onPressed: () => attempt(
                        () => ref
                            .read(fileFolderRepositoryProvider)
                            .restore(f.id),
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
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
            attempt(copySelected),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, c) => useCompactLayout(context) || c.maxWidth < 650
              ? Column(
                  children: [
                    if (!isPhoneLayout(context))
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
                    Expanded(
                      child: isPhoneLayout(context)
                          ? MobileWorkspaceActions(
                              actionId: 'file',
                              query: search,
                              searchHint: context.l10n.t('filesSearch'),
                              onSearchChanged: (value) {
                                search = value;
                                _selectedFiles.clear();
                                reload();
                              },
                              onAdd:
                                  !_selecting &&
                                      !importing &&
                                      !_batchBusy &&
                                      (collection == FileCollection.folder ||
                                          collection == FileCollection.recent)
                                  ? _addOnPhone
                                  : null,
                              addLabel: context.l10n.isZh
                                  ? '添加文件'
                                  : 'Add files',
                              child: browser,
                            )
                          : browser,
                    ),
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

  String _phoneText(String zh, String en) => context.l10n.isZh ? zh : en;

  void _phoneHome() {
    select(FileCollection.folder);
    setState(() => _mobileHome = true);
  }

  void _phoneBack(List<WorkspaceFolder> folders) {
    final current = folders.where((f) => f.id == folderId).firstOrNull;
    if (collection == FileCollection.folder &&
        (current?.parentId == WorkspaceFolderRepository.customerFilesRootId ||
            folderId == WorkspaceFolderRepository.customerFilesRootId)) {
      select(FileCollection.customers);
    } else if (collection == FileCollection.folder &&
        current?.parentId != null) {
      select(FileCollection.folder, current!.parentId);
    } else {
      _phoneHome();
    }
  }

  void _customerFolderVisibility(bool visible) {
    setState(() => _showCustomerFolder = visible);
    _savePreferences();
    if (!visible && collection == FileCollection.customers) _phoneHome();
    reload();
  }

  Future<void> _phoneFolderMenu(WorkspaceFolder folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(folder.name)),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: Text(context.l10n.t('rename')),
            onTap: () => Navigator.pop(sheet, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(context.l10n.t('delete')),
            subtitle: Text(
              _phoneText(
                '文件夹删除会同步到已连接设备',
                'Folder deletion syncs to connected devices',
              ),
            ),
            onTap: () => Navigator.pop(sheet, 'delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'delete') await folderDelete(folder);
    if (!mounted) return;
    if (action == 'rename') {
      final name = await workspaceNameDialog(
        context,
        title: context.l10n.t('rename'),
        initial: folder.name,
      );
      if (name != null) {
        await attempt(
          () => ref.read(fileFolderRepositoryProvider).rename(folder.id, name),
        );
      }
    }
  }

  Future<void> _hideCustomerFolderMenu() async {
    final hide = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('mobile-hide-customer-folder'),
            leading: const Icon(Icons.hide_source),
            title: Text(_phoneText('移除客户文件入口', 'Hide customer files')),
            subtitle: Text(
              _phoneText(
                '仅在本机隐藏，不删除文件，不影响电脑',
                'Hide on this device only. Files and desktop stay unchanged.',
              ),
            ),
            onTap: () => Navigator.pop(sheet, true),
          ),
        ],
      ),
    );
    if (mounted && hide == true) _customerFolderVisibility(false);
  }

  Widget _phoneMoreMenu(bool crm) => PopupMenuButton<String>(
    key: const ValueKey('file-more-menu'),
    tooltip: _phoneText('更多选项', 'More options'),
    enabled: !_batchBusy,
    icon: const Icon(Icons.more_horiz),
    onSelected: (action) {
      if (action.startsWith('view:')) {
        setState(
          () => viewMode = FileViewMode.values.byName(action.substring(5)),
        );
      } else if (action.startsWith('sort:')) {
        sort = FileSort.values.byName(action.substring(5));
        reload();
      } else if (action == 'images' || action == 'files') {
        setState(() => imagesFirst = action == 'images');
      } else if (action == 'select') {
        setState(() {
          _selecting = !_selecting;
          _selectedFiles.clear();
        });
      } else if (action == 'deleted') {
        select(FileCollection.deleted);
      } else if (action == 'customers') {
        _customerFolderVisibility(!_showCustomerFolder);
      }
      _savePreferences();
    },
    itemBuilder: (_) => [
      for (final mode in [FileViewMode.small, FileViewMode.list])
        CheckedPopupMenuItem(
          value: 'view:${mode.name}',
          checked: viewMode == mode,
          child: Text(
            mode == FileViewMode.small
                ? _phoneText('相册', 'Gallery')
                : context.l10n.t('fileView_list'),
          ),
        ),
      const PopupMenuDivider(),
      for (final option in FileSort.values)
        CheckedPopupMenuItem(
          value: 'sort:${option.name}',
          checked: sort == option,
          child: Text(
            context.l10n.t(switch (option) {
              FileSort.modified => 'fileModified',
              FileSort.created => 'filesCreated',
              FileSort.name => 'filesName',
              FileSort.type => 'filesType',
              FileSort.size => 'filesSize',
            }),
          ),
        ),
      const PopupMenuDivider(),
      for (final first in [true, false])
        CheckedPopupMenuItem(
          value: first ? 'images' : 'files',
          checked: imagesFirst == first,
          child: Text(
            first
                ? _phoneText('图片在前', 'Images first')
                : _phoneText('文件在前', 'Files first'),
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'select',
        enabled: !_mobileHome || search.trim().isNotEmpty,
        child: Text(
          _selecting
              ? _phoneText('完成选择', 'Done selecting')
              : _phoneText('多选', 'Select files'),
        ),
      ),
      PopupMenuItem(
        value: 'deleted',
        child: Text(context.l10n.t('noteDeleted')),
      ),
      if (crm)
        CheckedPopupMenuItem(
          value: 'customers',
          checked: _showCustomerFolder,
          child: Text(_phoneText('显示客户文件', 'Show customer files')),
        ),
    ],
  );

  List<MobileFileFolder> _phoneFolders(
    List<WorkspaceFolder> folders,
    List<FileBrowserEntry> entries,
    bool crm,
  ) {
    final term = search.trim();
    final ids = folders.map((f) => f.id).toSet();
    final children = folders.where((f) {
      if (f.id == WorkspaceFolderRepository.customerFilesRootId) return false;
      if (_mobileHome) {
        return term.isEmpty
            ? f.parentId == null || !ids.contains(f.parentId)
            : FuzzyMatch.matches(term, [f.name]);
      }
      if (collection == FileCollection.customers) {
        return f.parentId == WorkspaceFolderRepository.customerFilesRootId &&
            (term.isEmpty || FuzzyMatch.matches(term, [f.name]));
      }
      return collection == FileCollection.folder &&
          folderId != null &&
          f.parentId == folderId &&
          (term.isEmpty || FuzzyMatch.matches(term, [f.name]));
    }).toList();
    children.sort(
      (a, b) => switch (sort) {
        FileSort.modified =>
          (b.updatedAt?.millisecondsSinceEpoch ?? b.sortOrder).compareTo(
            a.updatedAt?.millisecondsSinceEpoch ?? a.sortOrder,
          ),
        FileSort.created =>
          (b.createdAt?.millisecondsSinceEpoch ?? b.sortOrder).compareTo(
            a.createdAt?.millisecondsSinceEpoch ?? a.sortOrder,
          ),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      },
    );
    final customerTitle = context.l10n.t('filesCustomers');
    return [
      if (_mobileHome &&
          crm &&
          _showCustomerFolder &&
          (term.isEmpty || FuzzyMatch.matches(term, [customerTitle])))
        MobileFileFolder(
          id: 'customers',
          name: customerTitle,
          icon: Icons.folder_shared_rounded,
          onOpen: () => select(FileCollection.customers),
          onLongPress: () => unawaited(_hideCustomerFolderMenu()),
        ),
      for (final folder in children)
        MobileFileFolder(
          id: folder.id,
          name: folder.name,
          onOpen: () => select(FileCollection.folder, folder.id),
          onLongPress: () => unawaited(_phoneFolderMenu(folder)),
        ),
      if (_mobileHome && term.isEmpty && entries.isNotEmpty)
        MobileFileFolder(
          id: 'unfiled',
          name: _phoneText('未分类文件', 'Unfiled files'),
          subtitle: _phoneText(
            '${entries.length} 个项目',
            '${entries.length} items',
          ),
          onOpen: () => select(FileCollection.folder),
          onLongPress: () => select(FileCollection.folder),
        ),
    ];
  }

  Widget _phoneBrowser(AsyncValue<List<WorkspaceFolder>> folders, bool crm) {
    final all = folders.valueOrNull ?? <WorkspaceFolder>[];
    final deletedFolders = collection == FileCollection.deleted
        ? ref.watch(deletedFileFoldersProvider).valueOrNull ??
              <WorkspaceFolder>[]
        : <WorkspaceFolder>[];
    final title = _mobileHome
        ? null
        : switch (collection) {
            FileCollection.customers => context.l10n.t('filesCustomers'),
            FileCollection.deleted => context.l10n.t('noteDeleted'),
            FileCollection.recent => context.l10n.t('noteRecent'),
            FileCollection.folder =>
              all.where((f) => f.id == folderId).firstOrNull?.name ??
                  _phoneText('未分类文件', 'Unfiled files'),
          };
    return PopScope(
      canPop: _mobileHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _phoneBack(all);
      },
      child: MobileWorkspaceActions(
        actionId: 'file',
        query: search,
        searchHint: context.l10n.t('filesSearch'),
        showSearchButton: false,
        onSearchChanged: (_) {},
        onAdd:
            !_selecting &&
                !importing &&
                !_batchBusy &&
                (collection == FileCollection.folder ||
                    collection == FileCollection.customers ||
                    collection == FileCollection.recent)
            ? _addOnPhone
            : null,
        addLabel: _phoneText('添加文件', 'Add files'),
        child: Material(
          color: context.flyColors.surface,
          child: Column(
            children: [
              MobileFilesHeader(
                query: search,
                title: title,
                searchHint: _phoneText('搜索文件和文件夹', 'Search files and folders'),
                onBack: () => _phoneBack(all),
                menu: _phoneMoreMenu(crm),
                onSearch: (value) {
                  search = value;
                  _selectedFiles.clear();
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
              Expanded(
                child: folders.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Center(child: Text(context.flyError(error))),
                  data: (items) => StreamBuilder<List<FileBrowserEntry>>(
                    stream: rows,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: TextButton(
                            onPressed: reload,
                            child: Text(context.l10n.t('filesLoadError')),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final entries = snapshot.data!;
                      final directories = _phoneFolders(items, entries, crm);
                      final visible = _mobileHome && search.trim().isEmpty
                          ? <FileBrowserEntry>[]
                          : entries;
                      return fileResults(
                        visible,
                        precedingSlivers: [
                          if (deletedFolders.isNotEmpty)
                            SliverList.builder(
                              itemCount: deletedFolders.length,
                              itemBuilder: (_, index) {
                                final folder = deletedFolders[index];
                                return ListTile(
                                  key: ValueKey(
                                    'mobile-restore-folder-${folder.id}',
                                  ),
                                  leading: const Icon(Icons.folder_outlined),
                                  title: Text(folder.name),
                                  trailing: IconButton(
                                    tooltip: context.l10n.t('restore'),
                                    icon: const Icon(Icons.restore),
                                    onPressed: () => attempt(
                                      () => ref
                                          .read(fileFolderRepositoryProvider)
                                          .restore(folder.id),
                                    ),
                                  ),
                                );
                              },
                            ),
                          if (directories.isNotEmpty)
                            MobileFileFoldersSliver(
                              folders: directories,
                              list: viewMode == FileViewMode.list,
                            ),
                          if (directories.isEmpty &&
                              visible.isEmpty &&
                              deletedFolders.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Text(context.l10n.t('filesEmpty')),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneListing(List<FileBrowserEntry> entries, List<Widget> folders) =>
      CustomScrollView(
        key: const ValueKey('mobile-files-content'),
        slivers: [
          ...folders,
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 112),
            sliver: viewMode == FileViewMode.list
                ? SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: tile(entries[i]),
                    ),
                  )
                : SliverLayoutBuilder(
                    builder: (context, constraints) => SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 150,
                        mainAxisExtent:
                            118 +
                            MediaQuery.textScalerOf(context).scale(26) -
                            26,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (_, i) => tile(entries[i]),
                    ),
                  ),
          ),
        ],
      );

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

  Widget fileResults(
    List<FileBrowserEntry> entries, {
    List<Widget> precedingSlivers = const [],
  }) {
    if (isPhoneLayout(context)) {
      entries = [
        ...entries.where(
          (e) => e.file.mimeType.startsWith('image/') == imagesFirst,
        ),
        ...entries.where(
          (e) => e.file.mimeType.startsWith('image/') != imagesFirst,
        ),
      ];
    }
    final listing = isPhoneLayout(context)
        ? _phoneListing(entries, precedingSlivers)
        : viewMode != FileViewMode.list
        ? GridView.builder(
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              isPhoneLayout(context) ? 144 : 12,
            ),
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
                width: useCompactLayout(context)
                    ? constraints.maxWidth
                    : constraints.maxWidth.clamp(800, double.infinity),
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    isPhoneLayout(context) ? 144 : 12,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (_, i) => Padding(
                    padding: EdgeInsets.only(
                      bottom:
                          ref.watch(flyPaletteProvider) == FlyPaletteId.clarity
                          ? 0
                          : 6,
                    ),
                    child: tile(entries[i]),
                  ),
                ),
              ),
            ),
          );
    final selected = entries
        .where((f) => _selectedFiles.contains(f.file.id))
        .toList();
    return Column(
      children: [
        if (_batchBusy)
          LinearProgressIndicator(
            key: const ValueKey('files-batch-progress'),
            value: _batchTotal == 0 ? null : _batchDone / _batchTotal,
          ),
        Expanded(child: listing),
        if (_selecting)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                key: const ValueKey('files-selection-bar'),
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '已选 ${selected.length} 项',
                    key: const ValueKey('files-selection-count'),
                  ),
                  TextButton(
                    key: const ValueKey('files-select-all'),
                    onPressed: _batchBusy
                        ? null
                        : () => setState(() {
                            if (selected.length == entries.length) {
                              _selectedFiles.clear();
                            } else {
                              _selectedFiles.addAll(
                                entries.map((f) => f.file.id),
                              );
                            }
                          }),
                    child: Text(
                      selected.length == entries.length ? '取消全选' : '全选',
                    ),
                  ),
                  if (collection != FileCollection.deleted)
                    TextButton.icon(
                      key: const ValueKey('files-batch-share'),
                      onPressed: _batchBusy || selected.isEmpty
                          ? null
                          : () => attempt(
                              () => _shareFiles(
                                selected.map((f) => f.file.id).toSet(),
                              ),
                            ),
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('分享'),
                    ),
                  TextButton.icon(
                    key: const ValueKey('files-batch-delete'),
                    onPressed: _batchBusy || selected.isEmpty
                        ? null
                        : () => attempt(() => _deleteFiles(selected)),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(
                      collection == FileCollection.deleted ? '永久删除' : '删除',
                    ),
                  ),
                  TextButton(
                    onPressed: _batchBusy
                        ? null
                        : () => setState(() {
                            _selecting = false;
                            _selectedFiles.clear();
                          }),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget tile(FileBrowserEntry entry) {
    final f = entry.file;
    final chosen = _selecting
        ? _selectedFiles.contains(f.id)
        : selectedId == f.id;
    final cardStyle =
        ref.watch(flyPaletteProvider) != FlyPaletteId.clarity ||
        viewMode != FileViewMode.list;
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
      color: ref.watch(flyPaletteProvider) == FlyPaletteId.clarity
          ? null
          : context.flyColors.accent,
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
                fit: isPhoneLayout(context) && viewMode != FileViewMode.list
                    ? BoxFit.cover
                    : BoxFit.contain,
                errorBuilder: (_, _, _) => icon,
              ),
      );
    }
    final content = isPhoneLayout(context) && viewMode != FileViewMode.list
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox.expand(child: visual),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          )
        : FileEntryContent(
            entry: entry,
            mode: viewMode,
            visual: visual,
            compact: useCompactLayout(context),
            onMenu: _selecting ? null : (point) => menu(entry, point),
            onCustomer: _selecting || entry.customerId == null
                ? null
                : () {
                    ref.read(selectedCustomerIdProvider.notifier).state =
                        entry.customerId;
                    if (useCompactLayout(context)) {
                      showCustomerDetailSheet(context, entry.customerId!);
                    } else {
                      context.go('/customers/all');
                    }
                  },
            onOrder: _selecting || entry.orderId == null
                ? null
                : () {
                    ref.read(orderCustomerFilterProvider.notifier).state = null;
                    ref.read(selectedOrderIdProvider.notifier).state =
                        entry.orderId;
                    if (useCompactLayout(context)) {
                      showOrderDetailSheet(context, entry.orderId!);
                    } else {
                      context.go('/orders/all');
                    }
                  },
          );
    final card = Material(
      key: ValueKey('file-item-${f.id}'),
      color: chosen
          ? context.flyColors.selected
          : cardStyle
          ? context.flyColors.surface
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardStyle ? 12 : 8),
        side: cardStyle
            ? BorderSide(
                color: chosen
                    ? context.flyColors.accent.withValues(alpha: .48)
                    : context.flyColors.divider,
              )
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (_selecting) {
            if (!_batchBusy) _toggleSelection(f.id);
            return;
          }
          setState(() => selectedId = f.id);
          if (f.deletedAt == null) attempt(() => open(entry));
        },
        onSecondaryTapUp: _selecting || _batchBusy
            ? null
            : (d) => menu(entry, d.globalPosition),
        onLongPress: isPhoneLayout(context) && !_selecting && !_batchBusy
            ? () => menu(entry, Offset.zero)
            : null,
        child: Padding(
          padding: EdgeInsets.all(viewMode == FileViewMode.list ? 0 : 8),
          child: Stack(
            children: [
              content,
              if (_selecting)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Checkbox(
                    key: ValueKey('file-check-${f.id}'),
                    value: chosen,
                    onChanged: _batchBusy
                        ? null
                        : (_) => _toggleSelection(f.id),
                  ),
                ),
              if (!_selecting &&
                  !isPhoneLayout(context) &&
                  Platform.isWindows &&
                  f.deletedAt == null)
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
    final transferable =
        !_selecting &&
            !isPhoneLayout(context) &&
            Platform.isWindows &&
            f.deletedAt == null
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
    return !_selecting &&
            !isPhoneLayout(context) &&
            f.ownerType == 'library' &&
            f.deletedAt == null
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
