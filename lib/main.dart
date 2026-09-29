import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';
import 'core/storage/data_root_providers.dart';
import 'core/storage/data_root_service.dart';
import 'features/customers/data/drift_customer_repository.dart';
import 'features/customers/domain/customer.dart';
import 'features/customers/presentation/customer_providers.dart';
import 'features/orders/data/drift_order_repository.dart';
import 'features/orders/domain/order.dart';
import 'features/orders/presentation/order_providers.dart';
import 'features/tasks/data/drift_task_repository.dart';
import 'features/tasks/domain/task_repository.dart';
import 'features/tasks/presentation/task_providers.dart';
import 'shared/data/tag_garbage_collector.dart';
import 'shared/backup/backup_providers.dart';
import 'shared/backup/backup_service.dart';
import 'shared/design_system/app_theme.dart';
import 'shared/design_system/design_tokens.dart';
import 'shared/design_system/fly_color_scheme.dart';
import 'shared/dev/release_capture.dart';
import 'shared/dev/first_run_demo_seeder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FlyBootstrap(dataRootService: FlyDataRootService()));
}

class FlyBootstrap extends StatefulWidget {
  const FlyBootstrap({required this.dataRootService, super.key});

  final FlyDataRootService dataRootService;

  @override
  State<FlyBootstrap> createState() => _FlyBootstrapState();
}

class _FlyBootstrapState extends State<FlyBootstrap> {
  AppDatabase? _database;
  Widget? _runtime;
  String? _currentRoot;
  String? _recommendedRoot;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await widget.dataRootService.loadDataRoot();
      final recommended = await widget.dataRootService.recommendedDataRoot();
      if (!mounted) return;
      _recommendedRoot = recommended;
      if (saved == null) {
        setState(() => _loading = false);
      } else {
        await _startRuntime(saved);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _startRuntime(String rootPath, {bool seedDemo = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    await widget.dataRootService.ensureStructure(rootPath);
    final database = AppDatabase.atDataRoot(rootPath);
    try {
      await database.ensureBuiltInData();
      final paletteSetting = await (database.select(
        database.appSettings,
      )..where((row) => row.key.equals('colorPalette'))).getSingleOrNull();
      final palette = FlyPaletteIdX.parse(paletteSetting?.value);
      final uiSettings = {
        for (final row in await database.select(database.appSettings).get())
          row.key: row.value,
      };
      await TagCleanupService(database).cleanupOrphanTags();
      final taskRepository = DriftTaskRepository(database);
      final customerRepository = DriftCustomerRepository(database);
      final orderRepository = DriftOrderRepository(database);
      if (seedDemo) {
        await FirstRunDemoSeeder(
          database: database,
          tasks: taskRepository,
          customers: customerRepository,
          orders: orderRepository,
        ).seedIfEligible();
      }
      var backupFailed = false;
      try {
        await FlyBackupService(
          database: database,
          dataRootPath: rootPath,
        ).runDailyBackupIfDue();
      } on Object catch (error) {
        // A failed automatic backup must not lock users out of their data.
        backupFailed = true;
        debugPrint('Fly automatic backup failed: $error');
      }
      final captured = await _captureSelection(
        taskRepository,
        customerRepository,
        orderRepository,
      );
      const capturePath = String.fromEnvironment('FLY_CAPTURE_PATH');
      final app = capturePath.isEmpty
          ? FlyApp(startupBackupFailed: backupFailed)
          : ReleaseCapture(
              outputPath: capturePath,
              child: FlyApp(startupBackupFailed: backupFailed),
            );
      final runtime = ProviderScope(
        key: ValueKey(rootPath),
        overrides: [
          databaseProvider.overrideWithValue(database),
          taskRepositoryProvider.overrideWithValue(
            taskRepository as TaskRepository,
          ),
          customerRepositoryProvider.overrideWithValue(customerRepository),
          orderRepositoryProvider.overrideWithValue(orderRepository),
          dataRootPathProvider.overrideWithValue(rootPath),
          flyPaletteProvider.overrideWith((ref) => palette),
          themeModeProvider.overrideWith(
            (ref) => ThemeMode.values.firstWhere(
              (v) => v.name == uiSettings['themeMode'],
              orElse: () => ThemeMode.system,
            ),
          ),
          localeProvider.overrideWith(
            (ref) => uiSettings['locale'] == 'en'
                ? const Locale('en')
                : const Locale('zh', 'CN'),
          ),
          dataRootActionsProvider.overrideWithValue(
            DataRootActions(
              changeTo: _changeDataRoot,
              open: () => widget.dataRootService.openInFileManager(rootPath),
            ),
          ),
          backupRuntimeActionsProvider.overrideWithValue(
            BackupRuntimeActions(restoreFrom: _restoreBackup),
          ),
          if (captured.taskId != null)
            selectedTaskIdProvider.overrideWith((ref) => captured.taskId),
          if (captured.customerId != null)
            selectedCustomerIdProvider.overrideWith(
              (ref) => captured.customerId,
            ),
          if (captured.customerId != null && captured.customerExtension != null)
            customerDetailExtensionProvider.overrideWith(
              (ref) => captured.customerExtension!,
            ),
          if (captured.orderId != null)
            selectedOrderIdProvider.overrideWith((ref) => captured.orderId),
          if (captured.orderId != null && captured.orderExtension != null)
            orderExtensionProvider.overrideWith(
              (ref) => captured.orderExtension!,
            ),
        ],
        child: app,
      );
      if (!mounted) {
        await database.close();
        return;
      }
      setState(() {
        _database = database;
        _currentRoot = rootPath;
        _runtime = runtime;
        _loading = false;
      });
    } on Object {
      await database.close();
      rethrow;
    }
  }

  Future<String?> _changeDataRoot(String targetPath) async {
    final oldRoot = _currentRoot;
    final oldDatabase = _database;
    if (oldRoot == null || oldDatabase == null) return '当前数据目录不可用';
    if (mounted) {
      setState(() {
        _loading = true;
        _runtime = null;
      });
    }
    await WidgetsBinding.instance.endOfFrame;
    await oldDatabase.close();
    _database = null;
    try {
      await widget.dataRootService.migrateDataRoot(oldRoot, targetPath);
      await _startRuntime(targetPath);
      return null;
    } on Object catch (error) {
      await _startRuntime(oldRoot);
      return '$error';
    }
  }

  Future<String?> _restoreBackup(String packagePath) async {
    final root = _currentRoot;
    final currentDatabase = _database;
    if (root == null || currentDatabase == null) return '当前数据目录不可用';
    final service = FlyBackupService(
      database: currentDatabase,
      dataRootPath: root,
    );
    PreparedRestore? prepared;
    var databaseClosed = false;
    try {
      prepared = await service.prepareRestore(packagePath);
      final settings = await service.loadSettings();
      await service.createBackup(
        directory: settings.directory,
        preRestore: true,
      );
      if (mounted) {
        setState(() {
          _loading = true;
          _runtime = null;
        });
      }
      await WidgetsBinding.instance.endOfFrame;
      await currentDatabase.close();
      databaseClosed = true;
      _database = null;
      await service.commitRestore(prepared);
      prepared = null;
      await _startRuntime(root);
      return null;
    } on Object catch (error) {
      if (prepared != null) await prepared.dispose();
      if (databaseClosed) {
        try {
          await _startRuntime(root);
        } on Object {
          // The original restore error is more useful to the user.
        }
      }
      return '$error';
    }
  }

  @override
  void dispose() {
    final database = _database;
    if (database != null) unawaited(database.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_runtime != null) return _runtime!;
    return MaterialApp(
      title: 'Fly',
      debugShowCheckedModeBanner: false,
      theme: FlyTheme.light(),
      darkTheme: FlyTheme.dark(),
      home: _loading
          ? const _BootstrapLoading()
          : FlyFirstRunPage(
              service: widget.dataRootService,
              recommendedRoot: _recommendedRoot ?? '',
              error: _error,
              onReady: (path, seedDemo) =>
                  _startRuntime(path, seedDemo: seedDemo),
            ),
    );
  }
}

typedef _CapturedSelection = ({
  String? taskId,
  String? customerId,
  String? orderId,
  DetailExtensionType? customerExtension,
  OrderExtensionType? orderExtension,
});

Future<_CapturedSelection> _captureSelection(
  DriftTaskRepository tasks,
  DriftCustomerRepository customers,
  DriftOrderRepository orders,
) async {
  const selectTask = bool.fromEnvironment('FLY_CAPTURE_SELECT_TASK');
  const selectCustomer = bool.fromEnvironment('FLY_CAPTURE_SELECT_CUSTOMER');
  const selectOrder = bool.fromEnvironment('FLY_CAPTURE_SELECT_ORDER');
  const customerPanel = String.fromEnvironment(
    'FLY_CAPTURE_CUSTOMER_EXTENSION',
  );
  const orderPanel = String.fromEnvironment('FLY_CAPTURE_ORDER_EXTENSION');
  const route = String.fromEnvironment(
    'FLY_INITIAL_ROUTE',
    defaultValue: '/customers/today',
  );
  String? taskId;
  String? customerId;
  String? orderId;
  if (selectTask) {
    final values = route.startsWith('/tasks/list/')
        ? await tasks
              .watchTasksForList(route.substring('/tasks/list/'.length))
              .first
        : await tasks.watchTodayTasks(DateTime.now()).first;
    taskId = values.firstOrNull?.id;
  }
  if (selectCustomer) {
    final values = await customers
        .watchCustomers(
          const CustomerQuery(projection: CustomerProjection.today),
        )
        .first;
    customerId = values.firstOrNull?.id;
  }
  if (selectOrder) {
    final values = await orders
        .watchOrders(const OrderQuery(projection: OrderProjection.all))
        .first;
    if (values.isNotEmpty) {
      orderId = values
          .firstWhere(
            (order) => order.salesAmount > 0,
            orElse: () => values.first,
          )
          .id;
    }
  }
  return (
    taskId: taskId,
    customerId: customerId,
    orderId: orderId,
    customerExtension: customerId == null || customerPanel.isEmpty
        ? null
        : switch (customerPanel) {
            'notes' => DetailExtensionType.notes,
            'followUps' => DetailExtensionType.followUps,
            _ => DetailExtensionType.none,
          },
    orderExtension: orderId == null || orderPanel.isEmpty
        ? null
        : switch (orderPanel) {
            'orderDetails' => OrderExtensionType.orderDetails,
            'financial' => OrderExtensionType.financial,
            'notes' => OrderExtensionType.notes,
            _ => OrderExtensionType.none,
          },
  );
}

class _BootstrapLoading extends StatelessWidget {
  const _BootstrapLoading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator.adaptive()));
}

class FlyFirstRunPage extends StatefulWidget {
  const FlyFirstRunPage({
    required this.service,
    required this.recommendedRoot,
    required this.onReady,
    this.error,
    super.key,
  });

  final FlyDataRootService service;
  final String recommendedRoot;
  final String? error;
  final Future<void> Function(String path, bool seedDemo) onReady;

  @override
  State<FlyFirstRunPage> createState() => _FlyFirstRunPageState();
}

class _FlyFirstRunPageState extends State<FlyFirstRunPage> {
  late final TextEditingController _path;
  bool _busy = false;
  bool _seedDemo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(text: widget.recommendedRoot);
    _error = widget.error;
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _chooseFolder() async {
    final selected = await getDirectoryPath(
      initialDirectory: _path.text.trim().isEmpty ? null : _path.text.trim(),
      confirmButtonText: '选择此文件夹',
    );
    if (selected != null) setState(() => _path.text = selected);
  }

  Future<void> _continue() async {
    final path = _path.text.trim();
    if (path.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final inspection = await widget.service.inspect(path);
      var useExisting = false;
      var migrateLegacy = false;
      if (inspection.hasDatabase && mounted) {
        useExisting =
            await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('发现已有 Fly 数据'),
                content: const Text('此目录已有 fly.db。确认使用它并保留其中的数据？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('使用已有数据'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!useExisting) return;
      } else if (inspection.hasLegacyDatabase && mounted) {
        migrateLegacy =
            await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('迁移现有 Fly 数据'),
                content: const Text('检测到旧版本数据库。Fly 会复制数据库和附件到新目录，并保留原文件作为回退。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('迁移并继续'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!migrateLegacy) return;
      }
      await widget.service.prepareFirstRun(
        path,
        useExistingDatabase: useExisting,
        migrateLegacyDatabase: migrateLegacy,
      );
      await widget.onReady(
        inspection.path,
        _seedDemo && !useExisting && !migrateLegacy,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.flight_rounded,
                size: 42,
                color: FlyColors.accent,
              ),
              const SizedBox(height: 18),
              Text(
                '欢迎使用 Fly',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                '请选择数据保存目录。这里会保存客户、订单、任务、数据库、附件和备份。建议使用“文档\\FlyData”，不要放在桌面。',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('first-run-data-root'),
                      controller: _path,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Fly 数据目录',
                        prefixIcon: Icon(Icons.folder_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : _chooseFolder,
                    child: const Text('选择文件夹'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _seedDemo,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _seedDemo = value ?? false),
                title: const Text('添加演示数据（可选）'),
                subtitle: const Text('默认创建空白工作区。演示数据会真实保存在所选目录中，建议使用单独的测试目录。'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: FlyColors.danger)),
              ],
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('first-run-start'),
                  onPressed: _busy ? null : _continue,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward, size: 17),
                  label: const Text('选择文件夹并开始'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
