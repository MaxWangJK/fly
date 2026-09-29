import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/note_repository.dart';
import '../domain/note_block.dart';

/// Serializes saves so typing during an in-flight write cannot be lost.
/// The workspace must await [flush] before switching notes or closing.
class NoteEditSession extends ChangeNotifier {
  NoteEditSession({
    required this.repository,
    required this.id,
    required this.title,
    required this.blocks,
    required this._revision,
    this.delay = const Duration(milliseconds: 600),
  });

  final NoteRepository repository;
  final String id;
  final Duration delay;
  String title;
  List<NoteBlock> blocks;
  int _revision;
  int _generation = 0;
  int _savedGeneration = 0;
  Timer? _timer;
  Future<void>? _pending;
  bool _disposed = false;
  Object? error;
  Object? draftError;
  Future<void> _draftWrites = Future.value();
  bool get draftProtected =>
      draftError == null && _protectedGeneration == _generation;
  int _protectedGeneration = 0;
  NoteDraft get draft =>
      NoteDraft(title: title, blocks: List.of(blocks), revision: _revision);
  void restore(NoteDraft saved, {required int currentRevision}) {
    _revision = saved.revision;
    if (currentRevision != saved.revision) error = NoteConflict();
    edit(title: saved.title, blocks: saved.blocks);
  }

  Future<String> recoverCopy() async {
    _timer?.cancel();
    if (_pending != null) {
      try {
        await _pending;
      } catch (_) {
        /* Copy retains the draft. */
      }
    }
    await _draftWrites;
    if (draftError != null) throw draftError!;
    return repository.recoverCopy(id, draft);
  }

  bool get dirty => _generation != _savedGeneration;
  bool get saving => _pending != null;

  void edit({String? title, List<NoteBlock>? blocks}) {
    if (_disposed) throw StateError('编辑会话已关闭');
    if (title != null) this.title = title;
    if (blocks != null) this.blocks = List.unmodifiable(blocks);
    _generation++;
    final snapshot = draft;
    final generation = _generation;
    _draftWrites = _draftWrites.then((_) async {
      try {
        await repository.writeDraft(id, snapshot);
        draftError = null;
        _protectedGeneration = generation;
      } catch (e) {
        draftError = e;
      }
      if (!_disposed) notifyListeners();
    });
    _timer?.cancel();
    // A revision conflict requires explicit resolution, not repeated retries.
    if (error is! NoteConflict) {
      _timer = Timer(delay, () {
        unawaited(_autoSave());
      });
    }
    notifyListeners();
  }

  Future<void> _autoSave() async {
    try {
      await flush();
    } catch (_) {
      /* Exposed through error; retain draft. */
    }
  }

  Future<void> flush() async {
    _timer?.cancel();
    await _draftWrites;
    if (draftError != null) {
      error = draftError;
      throw draftError!;
    }
    if (_pending != null) {
      await _pending;
      if (dirty) await flush();
      return;
    }
    if (!dirty) return;
    if (error is NoteConflict) throw error!;
    final work = _saveLoop();
    _pending = work;
    if (!_disposed) notifyListeners();
    try {
      await work;
    } finally {
      _pending = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _saveLoop() async {
    try {
      while (dirty) {
        await _draftWrites;
        if (draftError != null) throw draftError!;
        final generation = _generation;
        final savedTitle = title;
        final savedBlocks = List<NoteBlock>.of(blocks);
        _revision = await repository.save(
          id,
          title: savedTitle,
          blocks: savedBlocks,
          expectedRevision: _revision,
        );
        _savedGeneration = generation;
        await repository.clearSavedDraft(id, savedTitle, savedBlocks);
      }
      error = null;
    } catch (failure) {
      error = failure;
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
