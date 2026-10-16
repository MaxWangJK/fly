import 'package:flutter/material.dart';

import 'fly_book_workspace.dart';

/// Legacy note/article links retain a safe library destination. Note data stays
/// in its existing tables; no note editor or search is exposed by the library.
class KnowledgeWorkspace extends StatelessWidget {
  const KnowledgeWorkspace({
    this.initialArticleId,
    this.initialNoteId,
    this.showNotes = false,
    this.standalone = false,
    super.key,
  });
  final String? initialArticleId, initialNoteId;
  final bool showNotes, standalone;
  @override
  Widget build(BuildContext context) =>
      FlyBookWorkspace(initialChapterId: initialArticleId);
}
