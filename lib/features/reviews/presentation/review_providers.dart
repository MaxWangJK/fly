import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tasks/presentation/task_providers.dart';
import '../data/daily_review_repository.dart';

final dailyReviewRepositoryProvider = Provider(
  (ref) => DailyReviewRepository(ref.watch(databaseProvider)),
);
final reviewSessionsProvider = Provider((ref) => <String, ReviewSession>{});
final recordedReviewDaysProvider = StreamProvider.autoDispose<List<String>>(
  (ref) => ref.watch(dailyReviewRepositoryProvider).watchRecordedDays(),
);
final reviewHistoryProvider =
    StreamProvider.autoDispose<List<ReviewHistoryEntry>>(
      (ref) => ref.watch(dailyReviewRepositoryProvider).watchHistory(),
    );
final reviewSessionProvider = FutureProvider.family<ReviewSession, String>((
  ref,
  day,
) async {
  final repository = ref.watch(dailyReviewRepositoryProvider);
  final session = ReviewSession(repository, day, await repository.answers(day));
  final sessions = ref.read(reviewSessionsProvider);
  sessions[day] = session;
  ref.onDispose(() {
    sessions.remove(day);
    session.dispose();
  });
  return session;
});
final reviewSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, int>, String>(
      (ref, day) => ref.watch(dailyReviewRepositoryProvider).summary(day),
    );

/// Retained across navigation; a failure keeps the latest pending fields for retry.
class ReviewSession extends ChangeNotifier {
  ReviewSession(this.repository, this.day, Map<String, String> initial)
    : values = {...initial};
  final DailyReviewRepository repository;
  final String day;
  final Map<String, String> values;
  final _pending = <String, String>{};
  Future<void>? _running;
  Object? error;
  bool _disposed = false;
  bool get saving => _running != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void edit(String field, String text) {
    values[field] = text;
    _pending[field] = text;
    _start();
    _notify();
  }

  void _start() {
    if (_running != null) return;
    error = null;
    _running = _drain().whenComplete(() {
      _running = null;
      if (error == null && _pending.isNotEmpty) _start();
      _notify();
    });
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final entry = _pending.entries.first;
      try {
        await repository.saveAnswer(day, entry.key, entry.value);
        if (_pending[entry.key] == entry.value) _pending.remove(entry.key);
      } catch (e) {
        error = e;
        return;
      }
    }
  }

  Future<void> flush() async {
    if (_pending.isNotEmpty) _start();
    while (_running != null) {
      await _running;
    }
    if (error != null) throw StateError('$error');
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
