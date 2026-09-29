import '../../../l10n/service_error_copy.dart';

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../l10n/fly_localizations.dart';
import '../../../shared/attachments/attachment_providers.dart';
import '../../../shared/data/workspace_folder_repository.dart';
import '../../../shared/design_system/fly_color_scheme.dart';
import '../../../shared/design_system/workspace_folder_tree.dart';
import '../../files/data/managed_file_repository.dart';
import '../../files/presentation/file_providers.dart';
import '../domain/note_block.dart';
import 'note_block_editor.dart';
import 'note_edit_session.dart';
import 'note_providers.dart';
import 'note_tags_editor.dart';

class NotesWorkspace extends ConsumerStatefulWidget {
  const NotesWorkspace({this.initialNoteId, super.key});
  final String? initialNoteId;
  @override
  ConsumerState<NotesWorkspace> createState() => _NotesWorkspaceState();
}

class _NotesWorkspaceState extends ConsumerState<NotesWorkspace> {
  String mode = 'recent';
  String search = '';
  String? folderId, selectedId;
  Stream<List<WorkspaceNoteRecord>>? stream;
  final createTitle = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    selectedId = widget.initialNoteId;
  }

  @override
  void dispose() {
    createTitle.dispose();
    super.dispose();
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

  Future<void> flush() async {
    if (selectedId != null) {
      final session = ref.read(noteSessionProvider(selectedId!)).valueOrNull;
      await session?.flush();
    }
  }

  Future<void> select(String? id) async {
    await attempt(() async {
      await flush();
      if (mounted) setState(() => selectedId = id);
    });
  }

  void filter(String next, [String? folder]) {
    mode = next;
    folderId = folder;
    setState(() => stream = null);
  }

  Future<void> create() async {
    if (busy) return;
    final untitled = context.l10n.t('noteUntitled');
    setState(() => busy = true);
    await attempt(() async {
      await flush();
      final title = createTitle.text.trim();
      final id = await ref
          .read(noteRepositoryProvider)
          .create(
            title.isEmpty ? untitled : title,
            folderId: mode == 'folder' ? folderId : null,
          );
      if (mounted) {
        createTitle.clear();
        setState(() => selectedId = id);
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> createFolder(String? parent) async {
    final name = await workspaceNameDialog(
      context,
      title: context.l10n.t('noteNewFolder'),
    );
    if (name != null) {
      await attempt(() async {
        final id = await ref
            .read(noteFolderRepositoryProvider)
            .create(name, parentId: parent);
        if (mounted) filter('folder', id);
      });
    }
  }

  Future<void> deleteFolder(WorkspaceFolder f) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.l10n.t('noteDeleteFolder')),
        content: Text('${f.name}\n${context.l10n.t('noteDeleteFolderBody')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(context.l10n.t('delete')),
          ),
        ],
      ),
    );
    if (yes == true) {
      await attempt(() async {
        await flush();
        await ref.read(noteFolderRepositoryProvider).remove(f.id);
        if (mounted) {
          selectedId = null;
          filter('recent');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(noteRepositoryProvider);
    stream ??= repository.watch(
      folderId: folderId,
      recent: mode == 'recent',
      favorites: mode == 'favorites',
      deleted: mode == 'deleted',
      search: search,
    );
    final sidebar = Material(
      color: context.flyColors.secondarySidebar,
      child: Column(
        children: [
          ListTile(title: Text(context.l10n.t('noteWorkspace'))),
          for (final item in [
            ('recent', context.l10n.t('noteRecent'), Icons.history),
            ('favorites', context.l10n.t('noteFavorites'), Icons.star_outline),
          ])
            ListTile(
              dense: true,
              selected: mode == item.$1,
              leading: Icon(item.$3),
              title: Text(item.$2),
              onTap: () => filter(item.$1),
            ),
          ListTile(
            dense: true,
            title: Text(context.l10n.t('noteRoot')),
            onTap: () => filter('folder'),
            trailing: IconButton(
              tooltip: context.l10n.t('noteNewFolder'),
              onPressed: () => createFolder(null),
              icon: const Icon(Icons.add),
            ),
          ),
          Expanded(
            child: ref
                .watch(noteFoldersProvider)
                .when(
                  data: (folders) => WorkspaceFolderTree(
                    folders: folders,
                    selectedId: folderId,
                    onSelect: (id) => filter('folder', id),
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
                              .read(noteFolderRepositoryProvider)
                              .rename(f.id, name),
                        );
                      }
                    },
                    onDelete: deleteFolder,
                  ),
                  error: (e, _) => Text(context.flyError(e)),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.delete_outline),
            title: Text(context.l10n.t('noteDeleted')),
            onTap: () => filter('deleted'),
          ),
        ],
      ),
    );
    final list = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            key: const ValueKey('new-note-title'),
            controller: createTitle,
            enabled: !busy,
            decoration: InputDecoration(
              hintText: context.l10n.t('noteCreateHint'),
              suffixIcon: IconButton(
                tooltip: context.l10n.t('noteNew'),
                onPressed: busy ? null : create,
                icon: const Icon(Icons.add),
              ),
            ),
            onSubmitted: (_) => create(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.l10n.t('noteSearch'),
            ),
            onChanged: (value) => setState(() {
              search = value;
              stream = null;
            }),
          ),
        ),
        if (mode == 'deleted')
          StreamBuilder<List<WorkspaceFolder>>(
            stream: ref.read(noteFolderRepositoryProvider).watch(deleted: true),
            builder: (context, s) => Wrap(
              children: [
                for (final f in s.data ?? <WorkspaceFolder>[])
                  TextButton(
                    onPressed: () => attempt(
                      () =>
                          ref.read(noteFolderRepositoryProvider).restore(f.id),
                    ),
                    child: Text('${context.l10n.t('restore')} ${f.name}'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: StreamBuilder<List<WorkspaceNoteRecord>>(
            stream: stream,
            builder: (context, s) {
              if (s.hasError) {
                return Center(
                  child: Text(
                    '${context.l10n.t('noteLoadError')}: ${context.flyError(s.error)}',
                  ),
                );
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.data!.isEmpty) {
                return Center(child: Text(context.l10n.t('noteEmpty')));
              }
              return ListView.builder(
                itemCount: s.data!.length,
                itemBuilder: (context, index) {
                  final note = s.data![index];
                  final menuKey = GlobalKey<PopupMenuButtonState<String>>();
                  return GestureDetector(
                    onSecondaryTap: () =>
                        menuKey.currentState?.showButtonMenu(),
                    child: ListTile(
                      selected: selectedId == note.id,
                      title: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      dense: true,
                      leading: note.isFavorite
                          ? const Icon(Icons.star, size: 16)
                          : null,
                      onTap: note.deletedAt == null
                          ? () => select(note.id)
                          : null,
                      trailing: PopupMenuButton<String>(
                        key: menuKey,
                        tooltip: context.l10n.t('noteActions'),
                        itemBuilder: (_) => note.deletedAt != null
                            ? [
                                PopupMenuItem(
                                  value: 'restore',
                                  child: Text(context.l10n.t('restore')),
                                ),
                              ]
                            : [
                                if (mode == 'folder' && search.isEmpty) ...[
                                  PopupMenuItem(
                                    value: 'up',
                                    child: Text(context.l10n.t('noteMoveUp')),
                                  ),
                                  PopupMenuItem(
                                    value: 'down',
                                    child: Text(context.l10n.t('noteMoveDown')),
                                  ),
                                ],
                                PopupMenuItem(
                                  value: 'favorite',
                                  child: Text(
                                    context.l10n.t(
                                      note.isFavorite
                                          ? 'noteUnfavorite'
                                          : 'noteFavorites',
                                    ),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'move',
                                  child: Text(context.l10n.t('noteMoveFolder')),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(context.l10n.t('noteTrash')),
                                ),
                              ],
                        onSelected: (action) => attempt(() async {
                          if (action == 'up' || action == 'down') {
                            await repository.moveInFolder(
                              note.id,
                              action == 'up' ? -1 : 1,
                            );
                          }
                          if (action == 'favorite') {
                            await repository.favorite(
                              note.id,
                              !note.isFavorite,
                            );
                          }
                          if (action == 'restore') {
                            await repository.restore(note.id);
                            ref.invalidate(noteSessionProvider(note.id));
                          }
                          if (action == 'delete') {
                            await flush();
                            await repository.remove(note.id);
                            ref.invalidate(noteSessionProvider(note.id));
                            if (mounted && selectedId == note.id) {
                              setState(() => selectedId = null);
                            }
                          }
                          if (action == 'move') {
                            if (!context.mounted) return;
                            final folders =
                                ref.read(noteFoldersProvider).valueOrNull ?? [];
                            final target = await showDialog<String>(
                              context: context,
                              builder: (c) => SimpleDialog(
                                title: Text(context.l10n.t('noteMoveFolder')),
                                children: [
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(c, ''),
                                    child: Text(context.l10n.t('noteRoot')),
                                  ),
                                  for (final f in folders)
                                    SimpleDialogOption(
                                      onPressed: () => Navigator.pop(c, f.id),
                                      child: Text(f.name),
                                    ),
                                ],
                              ),
                            );
                            if (target != null) {
                              await repository.move(
                                note.id,
                                target.isEmpty ? null : target,
                              );
                            }
                          }
                        }),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
    final editor = selectedId == null
        ? Center(child: Text(context.l10n.t('noteSelect')))
        : ref
              .watch(noteSessionProvider(selectedId!))
              .when(
                data: (session) => _NoteDocument(
                  key: ValueKey(selectedId),
                  session: session,
                  onRecovered: (id) {
                    ref.invalidate(noteSessionProvider(session.id));
                    setState(() => selectedId = id);
                  },
                ),
                error: (e, _) => Center(child: Text(context.flyError(e))),
                loading: () => const Center(child: CircularProgressIndicator()),
              );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): create,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            attempt(flush),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 700) {
              return Column(
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          builder: (_) => SizedBox(height: 500, child: sidebar),
                        ),
                        icon: const Icon(Icons.folder_outlined),
                        label: Text(context.l10n.t('noteFolders')),
                      ),
                      if (selectedId != null)
                        TextButton(
                          onPressed: () => select(null),
                          child: Text(context.l10n.t('noteBack')),
                        ),
                    ],
                  ),
                  Expanded(child: selectedId == null ? list : editor),
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 190, child: sidebar),
                const VerticalDivider(width: 1),
                SizedBox(width: c.maxWidth < 1000 ? 230 : 280, child: list),
                const VerticalDivider(width: 1),
                Expanded(child: editor),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NoteDocument extends ConsumerStatefulWidget {
  const _NoteDocument({
    required this.session,
    required this.onRecovered,
    super.key,
  });
  final NoteEditSession session;
  final ValueChanged<String> onRecovered;
  @override
  ConsumerState<_NoteDocument> createState() => _NoteDocumentState();
}

class _NoteDocumentState extends ConsumerState<_NoteDocument> {
  late final title = TextEditingController(text: widget.session.title);
  bool importing = false;
  bool recovering = false;
  Future<void> recoverCopy() async {
    if (recovering) return;
    FocusScope.of(context).unfocus();
    setState(() => recovering = true);
    try {
      final id = await widget.session.recoverCopy();
      if (mounted) widget.onRecovered(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10n.t('noteRecoveryError')}: ${context.flyError(e)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => recovering = false);
    }
  }

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> media(NoteBlockType type, {String? replaceBlockId}) async {
    if (importing) return;
    final file = await openFile(
      acceptedTypeGroups: type == NoteBlockType.image
          ? [
              XTypeGroup(
                label: context.l10n.t('block_image'),
                extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
              ),
            ]
          : [],
    );
    if (file == null || !mounted) return;
    setState(() => importing = true);
    final storage = ref.read(managedFileStorageProvider);
    try {
      final imported = await storage.import(file.path);
      bool committed = false;
      try {
        final id = await ref
            .read(managedFileRepositoryProvider)
            .commit(
              imported,
              noteId: widget.session.id,
              duplicateAction: DuplicateFileAction.keepCopy,
            );
        committed = id != null;
        if (id != null) {
          final next = [...widget.session.blocks];
          final target = next.indexWhere((b) => b.id == replaceBlockId);
          final block = NoteBlock(
            id: const Uuid().v7(),
            type: type.name,
            content: {'attachmentId': id, 'caption': file.name},
          );
          if (target >= 0 &&
              next[target].knownType == NoteBlockType.paragraph &&
              ['', '/'].contains(next[target].content['text'])) {
            next[target] = block;
          } else if (target >= 0) {
            // The user typed during import: retain their text and insert after it.
            next.insert(target + 1, block);
          } else {
            next.add(block);
          }
          widget.session.edit(blocks: next);
          await widget.session.flush();
        }
      } finally {
        if (!committed) await storage.discard(imported);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.flyError(e))));
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) => AbsorbPointer(
      absorbing: recovering,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              controller: title,
              maxLength: 500,
              style: Theme.of(context).textTheme.headlineSmall,
              decoration: InputDecoration(
                hintText: context.l10n.t('noteTitle'),
                border: InputBorder.none,
                filled: false,
                counterText: '',
              ),
              onChanged: (v) => widget.session.edit(title: v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: StreamBuilder<WorkspaceNoteRecord?>(
              stream: widget.session.repository.watchNote(widget.session.id),
              builder: (context, snapshot) {
                final note = snapshot.data;
                if (note == null) return const SizedBox.shrink();
                final format = DateFormat('yyyy-MM-dd HH:mm');
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${context.l10n.t('noteCreated')}: ${format.format(note.createdAt)}  ·  ${context.l10n.t('fileModified')}: ${format.format(note.updatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.session.error != null
                        ? '${context.l10n.t(widget.session.draftProtected ? 'noteDraftProtected' : 'noteDraftUnsaved')}: ${context.flyError(widget.session.error)}'
                        : widget.session.saving
                        ? context.l10n.t('saving')
                        : widget.session.dirty
                        ? context.l10n.t('notePendingSave')
                        : context.l10n.t('saved'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (widget.session.error != null)
                  TextButton(
                    onPressed: recoverCopy,
                    child: Text(context.l10n.t('noteSaveCopy')),
                  ),
                if (widget.session.error != null)
                  TextButton(
                    onPressed: () async {
                      try {
                        await widget.session.flush();
                      } catch (_) {
                        /* Session displays the failure. */
                      }
                    },
                    child: Text(context.l10n.t('licenseRetryShort')),
                  ),
              ],
            ),
          ),
          if (importing) const LinearProgressIndicator(),
          Expanded(
            child: NoteBlockEditor(
              blocks: widget.session.blocks,
              onChanged: (v) => widget.session.edit(blocks: v),
              onAddMedia: media,
              onInsertMedia: (type, id) => media(type, replaceBlockId: id),
              mediaBuilder: (context, block) => _NoteMedia(block: block),
            ),
          ),
          NoteTagsEditor(
            key: ValueKey(widget.session.id),
            noteId: widget.session.id,
          ),
        ],
      ),
    ),
  );
}

class _NoteMedia extends ConsumerWidget {
  const _NoteMedia({required this.block});
  final NoteBlock block;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      FutureBuilder<AttachmentRecord?>(
        future: ref
            .read(managedFileRepositoryProvider)
            .find(block.content['attachmentId'] as String),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(context.l10n.t('noteAttachmentError'));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          final file = snapshot.data;
          if (file == null || file.deletedAt != null) {
            return Text(context.l10n.t('noteAttachmentMissing'));
          }
          final path = ref
              .read(managedFileStorageProvider)
              .absolute(file.relativePath);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.knownType == NoteBlockType.image)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: Image.file(
                    File(path),
                    cacheWidth: 1000,
                    errorBuilder: (_, _, _) =>
                        Text(context.l10n.t('fileImageUnavailable')),
                  ),
                ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await ref.read(attachmentOpenerProvider).open(path);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.flyError(e))),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.attach_file, size: 16),
                label: Text(file.originalName),
              ),
            ],
          );
        },
      );
}
