import '../../../l10n/service_error_copy.dart';
import '../../../l10n/crm_copy.dart';
import '../../../l10n/fly_localizations.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/design_system/design_tokens.dart';
import 'customer_import_service.dart';
import 'customer_import_providers.dart';
import 'customer_template_export.dart';
export 'customer_import_providers.dart' show customerImportServiceProvider;

class CustomerImportDialog extends ConsumerStatefulWidget {
  const CustomerImportDialog({super.key});

  @override
  ConsumerState<CustomerImportDialog> createState() =>
      _CustomerImportDialogState();
}

class _CustomerImportDialogState extends ConsumerState<CustomerImportDialog> {
  int _step = 0;
  String? _path;
  List<CustomerImportSheet> _sheets = const [];
  String? _sheetName;
  Map<int, CustomerImportField> _mapping = const {};
  List<CustomerImportRow> _preview = const [];
  DuplicateImportAction _duplicateAction = DuplicateImportAction.skip;
  CustomerImportResult? _result;
  bool _busy = false;
  String? _error;

  Future<void> _chooseFile() async {
    final file = await ref.read(customerImportFilePickerProvider)();
    if (file == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sheets = await ref
          .read(customerImportServiceProvider)
          .inspect(file.path);
      if (sheets.isEmpty) {
        throw StateError('工作簿中没有可用 Sheet');
      }
      if (mounted) {
        setState(() {
          _path = file.path;
          _sheets = sheets;
          _sheetName = sheets.first.name;
          _step = 1;
        });
        final mapping = ref
            .read(customerImportServiceProvider)
            .autoMap(sheets.first.headers);
        if ([
          CustomerImportField.name,
          CustomerImportField.country,
          CustomerImportField.category,
          CustomerImportField.status,
        ].every(mapping.containsValue)) {
          _mapping = mapping;
          await _buildPreview();
        }
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = context.flyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadTemplate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = ref
          .read(customerImportServiceProvider)
          .buildTemplate(
            translate: context.l10n.isZh
                ? null
                : (value) => crmEnglish[value] ?? value,
          );
      final box = context.findRenderObject() as RenderBox;
      final result = await ref
          .read(customerTemplateExporterProvider)
          .save(bytes, shareOrigin: box.localToGlobal(Offset.zero) & box.size);
      if (mounted && result != TemplateExportResult.cancelled) {
        setState(
          () => _error = context.l10n.isZh ? '模板已生成。姓名、国家、级别和状态为必填项。' : 'Template ready. Name, country, category and status are required.',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = context.flyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _prepareMapping() {
    final sheet = _sheets.firstWhere((item) => item.name == _sheetName);
    setState(() {
      _mapping = ref.read(customerImportServiceProvider).autoMap(sheet.headers);
      _step = 2;
    });
  }

  Future<void> _buildPreview() async {
    if (![
      CustomerImportField.name,
      CustomerImportField.country,
      CustomerImportField.category,
      CustomerImportField.status,
    ].every(_mapping.containsValue)) {
      setState(
        () => _error = context.l10n.isZh
            ? '请映射客户名称、国家、级别和状态。'
            : 'Map name, country, category and status.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await ref
          .read(customerImportServiceProvider)
          .preview(
            path: _path!,
            sheetName: _sheetName!,
            mapping: _mapping,
            requireProfile: true,
          );
      if (rows.isEmpty) throw const FormatException('表格没有客户数据，请先填写模板');
      if (mounted) {
        setState(() {
          _preview = rows;
          _step = 3;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = context.flyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(customerImportServiceProvider)
          .import(
            rows: _preview,
            duplicateAction: _duplicateAction,
            requireProfile: true,
          );
      if (mounted) {
        setState(() {
          _result = result;
          _step = 4;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = context.flyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
    title: Row(
      children: [
        Expanded(child: Text(context.crmCopy('导入客户'))),
        Text(switch (_step) {
          0 => context.crmCopy('选择文件'),
          1 => context.crmCopy('选择 Sheet'),
          2 => context.crmCopy('字段映射'),
          3 => context.crmCopy('预览与重复检查'),
          _ => context.crmCopy('导入结果'),
        }, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
    content: SizedBox(
      width: math.min(680, MediaQuery.sizeOf(context).width - 64),
      height: math.max(
        120,
        math.min(470, MediaQuery.sizeOf(context).height - 210),
      ),
      child: Column(
        children: [
          LinearProgressIndicator(value: (_step + 1) / 5),
          const SizedBox(height: FlySpacing.md),
          Expanded(child: _body(context)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      if (_step > 0 && _step < 4)
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step -= 1),
          child: Text(context.crmCopy('上一步')),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, _result),
        child: Text(_step == 4 ? context.crmCopy('完成') : context.crmCopy('取消')),
      ),
      if (_step == 1)
        FilledButton(
          onPressed: _busy ? null : _prepareMapping,
          child: Text(context.crmCopy('字段映射')),
        ),
      if (_step == 2)
        FilledButton(
          onPressed: _busy ? null : _buildPreview,
          child: Text(context.crmCopy('预览')),
        ),
      if (_step == 3)
        FilledButton(
          key: const ValueKey('confirm-customer-import'),
          onPressed: _busy ? null : _import,
          child: Text(context.crmCopy('开始导入')),
        ),
    ],
  );

  Widget _body(BuildContext context) {
    if (_busy) return const Center(child: CircularProgressIndicator.adaptive());
    return switch (_step) {
      0 => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.table_view_outlined, size: 34),
            const SizedBox(height: 12),
            Text(context.crmCopy('先下载 Fly 模板填写客户，或选择已有 .xlsx 文件。')),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _downloadTemplate,
                  icon: const Icon(Icons.download_outlined, size: 17),
                  label: Text(context.crmCopy('下载模板')),
                ),
                FilledButton.icon(
                  key: const ValueKey('choose-customer-import-file'),
                  onPressed: _chooseFile,
                  icon: const Icon(Icons.file_open_outlined, size: 17),
                  label: Text(context.crmCopy('选择 Excel')),
                ),
              ],
            ),
          ],
        ),
      ),
      1 => ListView(
        children: [
          Text(context.crmCopy('选择包含客户数据的 Sheet：')),
          const SizedBox(height: 10),
          RadioGroup<String>(
            groupValue: _sheetName,
            onChanged: (value) => setState(() => _sheetName = value),
            child: Column(
              children: [
                for (final sheet in _sheets)
                  RadioListTile<String>(
                    value: sheet.name,
                    title: Text(sheet.name),
                    subtitle: Text(
                      (context.l10n.isZh
                          ? '${sheet.headers.length} 列'
                          : '${sheet.headers.length} columns'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      2 => _mappingBody(),
      3 => _previewBody(),
      _ => _resultBody(),
    };
  }

  Widget _mappingBody() {
    final headers = _sheets
        .firstWhere((item) => item.name == _sheetName)
        .headers;
    return ListView.separated(
      itemCount: headers.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => Row(
        children: [
          Expanded(
            child: Text(
              headers[index].isEmpty
                  ? (context.l10n.isZh
                        ? '第 ${index + 1} 列'
                        : 'Column ${index + 1}')
                  : headers[index],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, size: 15),
          const SizedBox(width: 10),
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 600 ? 146 : 220,
            child: DropdownButton<CustomerImportField?>(
              value: _mapping[index],
              isExpanded: true,
              hint: Text(context.crmCopy('忽略')),
              items: [
                DropdownMenuItem<CustomerImportField?>(
                  value: null,
                  child: Text(context.crmCopy('忽略')),
                ),
                for (final field in CustomerImportField.values)
                  DropdownMenuItem<CustomerImportField?>(
                    value: field,
                    child: Text(context.crmCopy(field.label)),
                  ),
              ],
              onChanged: (value) => setState(() {
                final next = {..._mapping};
                next.removeWhere((key, field) => field == value);
                if (value == null) {
                  next.remove(index);
                } else {
                  next[index] = value;
                }
                _mapping = next;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewBody() {
    final duplicateCount = _preview
        .where((row) => row.status == CustomerImportRowStatus.duplicate)
        .length;
    final invalidCount = _preview
        .where((row) => row.status == CustomerImportRowStatus.invalid)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (context.l10n.isZh
              ? '共 ${_preview.length} 行 · 可能重复 $duplicateCount · 无效 $invalidCount'
              : '${_preview.length} rows · Duplicates $duplicateCount · Invalid $invalidCount'),
        ),
        if (duplicateCount > 0) ...[
          const SizedBox(height: 8),
          SegmentedButton<DuplicateImportAction>(
            segments: [
              ButtonSegment(
                value: DuplicateImportAction.skip,
                label: Text(context.crmCopy('跳过重复')),
              ),
              ButtonSegment(
                value: DuplicateImportAction.overwrite,
                label: Text(context.crmCopy('覆盖')),
              ),
              ButtonSegment(
                value: DuplicateImportAction.create,
                label: Text(context.crmCopy('仍然新增')),
              ),
            ],
            selected: {_duplicateAction},
            showSelectedIcon: false,
            onSelectionChanged: (values) =>
                setState(() => _duplicateAction = values.first),
          ),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            itemCount: _preview.length > 20 ? 20 : _preview.length,
            itemBuilder: (context, index) {
              final row = _preview[index];
              return ListTile(
                dense: true,
                leading: Icon(switch (row.status) {
                  CustomerImportRowStatus.ready => Icons.check_circle_outline,
                  CustomerImportRowStatus.duplicate => Icons.copy_outlined,
                  CustomerImportRowStatus.invalid => Icons.error_outline,
                }, size: 17),
                title: Text(row.values[CustomerImportField.name] ?? '—'),
                subtitle: Text(
                  '${context.l10n.isZh ? '第 ${row.rowNumber} 行' : 'Row ${row.rowNumber}'}${row.reason == null ? '' : ' · ${context.crmCopy(row.reason!)}'}',
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _resultBody() {
    final result = _result!;
    return ListView(
      children: [
        Text(
          context.crmCopy('导入完成'),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          (context.l10n.isZh
              ? '新增 ${result.created} · 覆盖 ${result.updated} · 跳过 ${result.skipped} · 失败 ${result.failedReasons.length}'
              : 'Created ${result.created} · Updated ${result.updated} · Skipped ${result.skipped} · Failed ${result.failedReasons.length}'),
        ),
        if (result.failedReasons.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            context.crmCopy('失败记录'),
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final reason in result.failedReasons) Text(reason),
        ],
      ],
    );
  }
}
