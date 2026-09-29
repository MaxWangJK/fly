import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/data/workspace_folder_repository.dart';
import '../../tasks/presentation/task_providers.dart';
import '../data/note_repository.dart';
import '../data/note_tag_repository.dart';
import '../../../core/database/app_database.dart';
import 'note_edit_session.dart';

final noteRepositoryProvider = Provider(
  (ref) => NoteRepository(ref.watch(databaseProvider)),
);
final noteTagRepositoryProvider = Provider(
  (ref) => NoteTagRepository(ref.watch(databaseProvider)),
);
final noteTagSuggestionsProvider = FutureProvider.autoDispose
    .family<List<TagRecord>, ({String noteId, String query})>(
      (ref, args) => ref
          .watch(noteTagRepositoryProvider)
          .suggestions(args.noteId, args.query),
    );
final noteTagsProvider = StreamProvider.autoDispose
    .family<List<TagRecord>, String>(
      (ref, id) => ref.watch(noteTagRepositoryProvider).watch(id),
    );
final noteSessionsProvider = Provider((ref) => <String, NoteEditSession>{});
final notePreviewProvider = StreamProvider.autoDispose.family<String, String>(
  (ref, id) => ref.watch(noteRepositoryProvider).watchPreview(id),
);
final noteFolderRepositoryProvider = Provider(
  (ref) => WorkspaceFolderRepository(
    ref.watch(databaseProvider),
    WorkspaceFolderKind.notes,
  ),
);
final noteFoldersProvider = StreamProvider(
  (ref) => ref.watch(noteFolderRepositoryProvider).watch(),
);
// Keep drafts and outstanding saves alive when another primary module is opened.
final noteSessionProvider = FutureProvider.family<NoteEditSession, String>((
  ref,
  id,
) async {
  final repository = ref.watch(noteRepositoryProvider);
  final note = await repository.get(id);
  if (note == null || note.deletedAt != null) throw StateError('笔记不存在或已删除');
  final session = NoteEditSession(
    repository: repository,
    id: id,
    title: note.title,
    blocks: await repository.blocks(id),
    revision: note.revision,
  );
  final sessions = ref.read(noteSessionsProvider);
  sessions[id] = session;
  ref.onDispose(() {
    if (identical(sessions[id], session)) sessions.remove(id);
    session.dispose();
  });
  final draft = await repository.readDraft(id);
  if (draft != null) {
    if (draft.matches(note.title, session.blocks)) {
      await repository.clearDraft(id, draft);
    } else {
      session.restore(draft, currentRevision: note.revision);
    }
  }
  return session;
});
