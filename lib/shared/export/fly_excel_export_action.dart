import '../../l10n/crm_copy.dart';
import '../../l10n/fly_localizations.dart';

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tasks/presentation/task_providers.dart';
import 'fly_excel_export_service.dart';

enum FlyExportOrigin { customers, orders }

Future<void> showFlyExcelExport(
  BuildContext context,
  WidgetRef ref, {
  required FlyExportOrigin origin,
  required Set<String> currentIds,
}) async {
  final scope = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.crmCopy('导出 Excel')),
      content: Text(context.crmCopy('选择导出当前筛选结果，或导出全部客户与订单。附件文件不会写入 Excel。')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(context.crmCopy('取消')),
        ),
        OutlinedButton(
          key: const ValueKey('export-current'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(context.crmCopy('当前筛选')),
        ),
        FilledButton(
          key: const ValueKey('export-all'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(context.crmCopy('全部数据')),
        ),
      ],
    ),
  );
  if (scope == null || !context.mounted) return;
  final now = DateTime.now();
  final name =
      'Fly-${origin == FlyExportOrigin.customers ? 'Customers' : 'Orders'}-'
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.xlsx';
  try {
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        XTypeGroup(label: context.crmCopy('Excel 工作簿'), extensions: ['xlsx']),
      ],
    );
    if (location == null || !context.mounted) return;
    final service = FlyExcelExportService(ref.read(databaseProvider));
    final bytes = await service.buildWorkbook(
      translate: context.l10n.isZh
          ? null
          : (value) => crmEnglish[value] ?? value,
      customerIds: scope && origin == FlyExportOrigin.customers
          ? currentIds
          : null,
      orderIds: scope && origin == FlyExportOrigin.orders ? currentIds : null,
    );
    await File(location.path).writeAsBytes(bytes, flush: true);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (context.l10n.isZh
              ? '已导出：${location.path}'
              : 'Exported: ${location.path}'),
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.isZh ? '导出失败：$error' : 'Export failed: $error',
        ),
      ),
    );
  }
}
