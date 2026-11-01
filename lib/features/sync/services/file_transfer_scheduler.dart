import 'dart:async';
import 'dart:collection';

/// Bound file I/O independently of the authority's ordered metadata transactions.
class FileTransferScheduler {
  FileTransferScheduler({this.limit = 2});
  final int limit;
  int _active = 0;
  final _waiting = Queue<Completer<void>>();
  final _keys = <String, Future<void>>{};

  Future<void> run(Future<void> Function() action, {String? key}) async {
    final previous = key == null ? null : _keys[key];
    final done = Completer<void>();
    if (key != null) _keys[key] = done.future;
    try {
      await previous;
      if (_active >= limit) {
        final ready = Completer<void>();
        _waiting.add(ready);
        await ready.future;
      } else {
        _active++;
      }
      try {
        await action();
      } finally {
        if (_waiting.isNotEmpty) {
          _waiting.removeFirst().complete();
        } else {
          _active--;
        }
      }
    } finally {
      done.complete();
      if (key != null && identical(_keys[key], done.future)) _keys.remove(key);
    }
  }
}
