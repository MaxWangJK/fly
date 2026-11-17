import 'dart:async';

/// Optional maintenance never starts during the initial working period or
/// while the user is typing, scrolling, or otherwise interacting with Fly.
class IdleMaintenanceScheduler {
  IdleMaintenanceScheduler({
    required this.run,
    DateTime Function()? now,
    this.startupDelay = const Duration(minutes: 5),
    this.idleDelay = const Duration(seconds: 90),
  }) : _now = now ?? DateTime.now {
    _notBefore = _now().add(startupDelay);
    _lastActivity = _now();
  }

  final Future<void> Function() run;
  final Duration startupDelay, idleDelay;
  final DateTime Function() _now;
  late DateTime _notBefore, _lastActivity;
  Timer? _timer;
  bool _pending = false, _paused = false, _running = false, _disposed = false;

  void request() {
    if (_disposed || _running) return;
    _pending = true;
    _schedule();
  }

  void activity() {
    if (_disposed) return;
    _lastActivity = _now();
    _schedule();
  }

  void pause() {
    _paused = true;
    _timer?.cancel();
  }

  void resume() {
    _paused = false;
    activity();
    request();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || _paused || _running || !_pending) return;
    final idleAt = _lastActivity.add(idleDelay);
    final due = idleAt.isAfter(_notBefore) ? idleAt : _notBefore;
    final wait = due.difference(_now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _execute);
  }

  Future<void> _execute() async {
    if (_disposed || _paused || !_pending) return;
    _pending = false;
    _running = true;
    try {
      await run();
    } finally {
      _running = false;
      _notBefore = _now().add(startupDelay);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
