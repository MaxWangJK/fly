import '../../core/database/app_database.dart';
import '../../features/customers/data/drift_customer_repository.dart';
import '../../features/orders/data/drift_order_repository.dart';
import '../../features/tasks/data/drift_task_repository.dart';

enum DemoSeedResult { seeded, alreadyInitialized, existingData }

class FirstRunDemoSeeder {
  FirstRunDemoSeeder({
    required this.database,
    required this.tasks,
    required this.customers,
    required this.orders,
  });

  static const version = 1;
  static const _settingKey = 'demoSeedVersion';

  final AppDatabase database;
  final DriftTaskRepository tasks;
  final DriftCustomerRepository customers;
  final DriftOrderRepository orders;

  Future<DemoSeedResult> seedIfEligible({DateTime? now}) async {
    final initialized = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(_settingKey))).getSingleOrNull();
    if (initialized != null) return DemoSeedResult.alreadyInitialized;

    final counts = await Future.wait<int>([
      database
          .customSelect('SELECT COUNT(*) AS c FROM customers')
          .map((row) => row.read<int>('c'))
          .getSingle(),
      database
          .customSelect('SELECT COUNT(*) AS c FROM orders')
          .map((row) => row.read<int>('c'))
          .getSingle(),
      database
          .customSelect('SELECT COUNT(*) AS c FROM tasks')
          .map((row) => row.read<int>('c'))
          .getSingle(),
    ]);
    if (counts.any((count) => count > 0)) {
      await _markInitialized(-1);
      return DemoSeedResult.existingData;
    }

    final timestamp = now ?? DateTime.now();
    final today = DateTime(timestamp.year, timestamp.month, timestamp.day);
    await tasks.seedDevelopmentData(today: today);
    final customerValues = await customers.seedDevelopmentData(today: today);
    await orders.seedDevelopmentData(customerValues, today: today);
    await _markInitialized(version);
    return DemoSeedResult.seeded;
  }

  Future<void> _markInitialized(int value) => database
      .into(database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: _settingKey,
          value: '$value',
          updatedAt: DateTime.now(),
        ),
      );
}
