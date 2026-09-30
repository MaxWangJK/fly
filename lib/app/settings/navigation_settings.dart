import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../features/tasks/presentation/task_providers.dart';

class NavigationSettings {
  const NavigationSettings({
    this.dashboardVisible = false,
    this.crmVisible = true,
    this.toolsVisible = true,
  });
  final bool dashboardVisible, crmVisible, toolsVisible;
  NavigationSettings copyWith({
    bool? dashboardVisible,
    bool? crmVisible,
    bool? toolsVisible,
  }) => NavigationSettings(
    dashboardVisible: dashboardVisible ?? this.dashboardVisible,
    crmVisible: crmVisible ?? this.crmVisible,
    toolsVisible: toolsVisible ?? this.toolsVisible,
  );
}

abstract final class StartupWorkspaceResolver {
  static String resolve(NavigationSettings settings) =>
      settings.dashboardVisible
      ? '/dashboard'
      : settings.crmVisible
      ? '/customers/today'
      : '/tasks/today';
  static bool allowed(String path, NavigationSettings settings) =>
      !(path.startsWith('/dashboard') && !settings.dashboardVisible) &&
      !(path.startsWith('/tools') && !settings.toolsVisible) &&
      !((path.startsWith('/customers') || path.startsWith('/orders')) &&
          !settings.crmVisible);
}

class NavigationSettingsController extends ChangeNotifier {
  NavigationSettingsController(this.db) {
    ready = _load();
  }
  final AppDatabase db;
  NavigationSettings value = const NavigationSettings();
  bool loaded = false;
  bool saving = false;
  String? error;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  late final Future<void> ready;
  static const key = 'navigationVisibility';
  Future<void> _load() async {
    try {
      final row = await (db.select(
        db.appSettings,
      )..where((r) => r.key.equals(key))).getSingleOrNull();
      if (row != null) {
        final data = jsonDecode(row.value) as Map<String, dynamic>;
        value = NavigationSettings(
          dashboardVisible: data['dashboardVisible'] == true,
          crmVisible: data['crmVisible'] != false,
          toolsVisible: data['toolsVisible'] != false,
        );
      }
    } catch (_) {
      error = '导航设置读取失败，暂时显示全部模块';
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> update(NavigationSettings next) async {
    await ready;
    if (saving) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: key,
              value: jsonEncode({
                'dashboardVisible': next.dashboardVisible,
                'crmVisible': next.crmVisible,
                'toolsVisible': next.toolsVisible,
              }),
              updatedAt: DateTime.now(),
            ),
          );
      value = next;
    } catch (_) {
      error = '保存失败，请重试；原设置已保留';
    }
    saving = false;
    notifyListeners();
  }
}

final navigationSettingsProvider =
    ChangeNotifierProvider<NavigationSettingsController>(
      (ref) => NavigationSettingsController(ref.watch(databaseProvider)),
    );
