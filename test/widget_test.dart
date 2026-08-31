import 'package:fly/features/tasks/domain/task.dart';
import 'package:fly/features/tasks/presentation/task_list_page.dart';
import 'package:fly/features/tasks/presentation/task_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('task list renders quick add and empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inboxTasksProvider.overrideWith(
            (ref) => Stream<List<FlyTask>>.value(const []),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TaskListPage(
              title: 'Inbox',
              collection: TaskCollection.inbox,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Add a task and press Enter'), findsOneWidget);
    expect(find.text('Clear runway'), findsOneWidget);
  });
}
