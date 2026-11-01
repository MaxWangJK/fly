import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tasks/presentation/task_providers.dart';
import '../data/daily_review_repository.dart';
import '../data/review_program_repository.dart';
import '../domain/review_program.dart';
import 'review_providers.dart';

final reviewProgramRepositoryProvider = Provider(
  (ref) => ReviewProgramRepository(ref.watch(databaseProvider)),
);
final reviewProgramPreferenceProvider = FutureProvider(
  (ref) => ref.watch(reviewProgramRepositoryProvider).load(),
);
final guidedReviewRepositoryProvider = Provider(
  (ref) => DailyReviewRepository(
    ref.watch(databaseProvider),
    fields: GuidedReview.fields,
    historyFields: GuidedReview.visibleFields,
  ),
);
final guidedReviewActionsProvider = Provider(
  (ref) => GuidedReviewActions(ref.watch(databaseProvider)),
);
final guidedReviewHistoryProvider =
    StreamProvider.autoDispose<List<ReviewHistoryEntry>>(
      (ref) => ref.watch(guidedReviewRepositoryProvider).watchHistory(),
    );
final guidedReviewSessionsProvider = Provider(
  (ref) => <String, ReviewSession>{},
);
final guidedReviewSessionProvider =
    FutureProvider.family<ReviewSession, String>((ref, day) async {
      final repository = ref.watch(guidedReviewRepositoryProvider);
      final session = ReviewSession(
        repository,
        day,
        await repository.answers(day),
      );
      final subscription = repository.watchAnswers(day).listen(session.receive);
      final sessions = ref.read(guidedReviewSessionsProvider);
      sessions[day] = session;
      ref.onDispose(() {
        unawaited(subscription.cancel());
        if (identical(sessions[day], session)) sessions.remove(day);
        session.dispose();
      });
      return session;
    });
