import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly/app/idle_maintenance_scheduler.dart';

void main() {
  testWidgets(
    'startup grace and continued interaction both delay maintenance',
    (tester) async {
      var runs = 0;
      final scheduler = IdleMaintenanceScheduler(
        now: tester.binding.clock.now,
        run: () async => runs++,
      )..request();
      addTearDown(scheduler.dispose);
      await tester.pump(const Duration(minutes: 4, seconds: 50));
      expect(runs, 0);
      scheduler.activity();
      await tester.pump(const Duration(seconds: 10));
      expect(runs, 0);
      await tester.pump(const Duration(seconds: 79));
      expect(runs, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(runs, 1);
      await tester.pump(const Duration(minutes: 15));
      expect(runs, 1);
    },
  );

  testWidgets('paused or disposed runtime does no maintenance', (tester) async {
    var runs = 0;
    final scheduler = IdleMaintenanceScheduler(
      now: tester.binding.clock.now,
      run: () async => runs++,
    )..request();
    scheduler.pause();
    await tester.pump(const Duration(minutes: 10));
    expect(runs, 0);
    scheduler.resume();
    await tester.pump(const Duration(seconds: 89));
    expect(runs, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(runs, 1);
    scheduler.request();
    scheduler.dispose();
    await tester.pump(const Duration(minutes: 10));
    expect(runs, 1);
  });

  testWidgets('maintenance requests coalesce without overlapping a worker', (
    tester,
  ) async {
    var runs = 0;
    final done = Completer<void>();
    final scheduler =
        IdleMaintenanceScheduler(
            now: tester.binding.clock.now,
            run: () {
              runs++;
              return done.future;
            },
          )
          ..request()
          ..request();
    addTearDown(scheduler.dispose);
    await tester.pump(const Duration(minutes: 5));
    expect(runs, 1);
    scheduler.request();
    await tester.pump(const Duration(minutes: 5));
    expect(runs, 1);
    done.complete();
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    expect(runs, 1);
  });
}
