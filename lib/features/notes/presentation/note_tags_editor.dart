import '../../../l10n/service_error_copy.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/fly_localizations.dart';
import 'note_providers.dart';

class NoteTagsEditor extends ConsumerStatefulWidget {
  const NoteTagsEditor({required this.noteId, super.key});
  final String noteId;
  @override
  ConsumerState<NoteTagsEditor> createState() => _NoteTagsEditorState();
}

class _NoteTagsEditorState extends ConsumerState<NoteTagsEditor> {
  final input = TextEditingController();
  bool busy = false;
  String? error;
  Future<void> add(String name) => change(() async {
    await ref.read(noteTagRepositoryProvider).add(widget.noteId, name);
    if (mounted) input.clear();
  });
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> change(Future<void> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => error = context.flyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = FlyLocalizations(Localizations.localeOf(context));
    final tags = ref.watch(noteTagsProvider(widget.noteId));
    final suggestions = input.text.trim().isEmpty || busy
        ? null
        : ref.watch(
            noteTagSuggestionsProvider((
              noteId: widget.noteId,
              query: input.text,
            )),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tags.isLoading) const LinearProgressIndicator(),
          if (tags.hasError) Text(l10n.t('noteTagsLoadError')),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in tags.valueOrNull ?? [])
                    InputChip(
                      label: Text(tag.name),
                      visualDensity: VisualDensity.compact,
                      deleteButtonTooltipMessage: l10n.t('removeNoteTag'),
                      onDeleted: busy
                          ? null
                          : () => change(
                              () => ref
                                  .read(noteTagRepositoryProvider)
                                  .remove(widget.noteId, tag.id),
                            ),
                    ),
                ],
              ),
            ),
          ),
          if (suggestions?.hasError == true)
            TextButton(
              onPressed: () => ref.invalidate(
                noteTagSuggestionsProvider((
                  noteId: widget.noteId,
                  query: input.text,
                )),
              ),
              child: Text(l10n.t('noteTagSuggestionsRetry')),
            ),
          if (suggestions?.valueOrNull?.isNotEmpty == true)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 96),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final tag in suggestions!.valueOrNull!)
                    TextButton(
                      key: ValueKey('note-tag-suggestion-${tag.id}'),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () => add(tag.name),
                      child: Text(
                        tag.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          TextField(
            key: const ValueKey('note-tag-input'),
            controller: input,
            enabled: !busy,
            maxLength: 81,
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              prefixIcon: const Icon(Icons.tag, size: 18),
              hintText: l10n.t('noteTagHint'),
              errorText: error,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: add,
          ),
        ],
      ),
    );
  }
}
