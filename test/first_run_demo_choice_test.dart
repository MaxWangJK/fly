import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/core/storage/data_root_service.dart';
import 'package:fly/main.dart';

void main() {
  for (final optIn in [false, true]) {
    testWidgets('first run demo opt-in is $optIn', (tester) async {
      bool? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: FlyFirstRunPage(
            service: _StubDataRootService(),
            recommendedRoot: 'E:\\FakeFlyData',
            onReady: (path, seedDemo) async {
              expect(path, 'E:\\FakeFlyData');
              chosen = seedDemo;
            },
          ),
        ),
      );
      expect(find.text('添加演示数据（可选）'), findsOneWidget);
      if (optIn) {
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('first-run-start')));
      await tester.pump();
      expect(chosen, optIn);
    });
  }
}

class _StubDataRootService extends FlyDataRootService {
  @override
  Future<DataRootInspection> inspect(String path) async => DataRootInspection(
    path: path,
    hasDatabase: false,
    hasLegacyDatabase: false,
  );

  @override
  Future<void> prepareFirstRun(
    String path, {
    required bool useExistingDatabase,
    required bool migrateLegacyDatabase,
  }) async {}
}
