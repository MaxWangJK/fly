import '../../../../../l10n/tools_copy.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/container_loading_models.dart';

const cargoPalette = [
  0xFF79A88C,
  0xFF7FA7C9,
  0xFFD8A06B,
  0xFF9A86BE,
  0xFF6EA6A0,
  0xFFBE879A,
  0xFFC1A568,
  0xFF8894BE,
];

Future<bool> confirmLoadingAction(
  BuildContext context,
  String text, {
  String action = '确认',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.toolsCopy(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.toolsCopy('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.toolsCopy(action)),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> loadingNameDialog(
  BuildContext context,
  String title,
  String initial,
) => showDialog<String>(
  context: context,
  builder: (context) => _LoadingNameDialog(title: title, initial: initial),
);

class _LoadingNameDialog extends StatefulWidget {
  const _LoadingNameDialog({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_LoadingNameDialog> createState() => _LoadingNameDialogState();
}

class _LoadingNameDialogState extends State<_LoadingNameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.toolsCopy(widget.title)),
    content: SizedBox(
      width: 350,
      child: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 160,
        onSubmitted: (v) => Navigator.pop(context, v),
        decoration: InputDecoration(labelText: context.toolsCopy('名称')),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.toolsCopy('取消')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: Text(context.toolsCopy('确定')),
      ),
    ],
  );
}

class CargoLibraryEditor extends StatefulWidget {
  const CargoLibraryEditor({this.cargo, this.duplicate = false, super.key});
  final CargoPackageModel? cargo;
  final bool duplicate;
  @override
  State<CargoLibraryEditor> createState() => _CargoLibraryEditorState();
}

class _CargoLibraryEditorState extends State<CargoLibraryEditor> {
  late final name = TextEditingController(
    text: widget.cargo == null
        ? ''
        : '${widget.cargo!.name}${widget.duplicate ? ' 副本' : ''}',
  );
  late final lengths = [
    for (final n in [
      widget.cargo?.dimensions.lengthMm,
      widget.cargo?.dimensions.widthMm,
      widget.cargo?.dimensions.heightMm,
    ])
      TextEditingController(text: n == null ? '' : _number(n / 10)),
  ];
  late final weight = TextEditingController(
    text: widget.cargo == null ? '' : _number(widget.cargo!.weightKg),
  );
  late final quantity = TextEditingController(
    text: widget.cargo?.defaultSectionQuantity?.toString() ?? '',
  );
  late CargoPackageType type = widget.cargo?.type ?? CargoPackageType.package;
  late int color = widget.cargo?.colorValue ?? cargoPalette.first;
  String unit = 'cm';
  String? error;
  @override
  void dispose() {
    name.dispose();
    weight.dispose();
    quantity.dispose();
    for (final c in lengths) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.cargo == null
          ? context.toolsCopy('添加货物')
          : widget.duplicate
          ? context.toolsCopy('复制规格')
          : context.toolsCopy('编辑货物'),
    ),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              maxLength: 160,
              decoration: InputDecoration(labelText: context.toolsCopy('名称')),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<CargoPackageType>(
                    initialValue: type,
                    decoration: InputDecoration(
                      labelText: context.toolsCopy('类型'),
                    ),
                    items: [
                      for (final item in [
                        (CargoPackageType.package, context.toolsCopy('包装')),
                        (CargoPackageType.pallet, context.toolsCopy('托盘')),
                        (CargoPackageType.crate, context.toolsCopy('木箱')),
                        (CargoPackageType.door, context.toolsCopy('门扇')),
                        (CargoPackageType.custom, context.toolsCopy('自定义')),
                      ])
                        DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                    ],
                    onChanged: (v) => setState(() => type = v!),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: unit,
                  items: [
                    for (final u in ['mm', 'cm', 'm'])
                      DropdownMenuItem(value: u, child: Text(u)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    final factor = _factor(unit) / _factor(v);
                    setState(() {
                      for (final c in lengths) {
                        final n = double.tryParse(c.text);
                        if (n != null) c.text = _number(n * factor);
                      }
                      unit = v;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: lengths[i],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: (type == CargoPackageType.door
                            ? [
                                context.toolsCopy('高度'),
                                context.toolsCopy('宽度'),
                                context.toolsCopy('厚度'),
                              ]
                            : [
                                context.toolsCopy('长度'),
                                context.toolsCopy('宽度'),
                                context.toolsCopy('高度'),
                              ])[i],
                        suffixText: unit,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: weight,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.toolsCopy('单件重量'),
                      suffixText: 'kg',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.toolsCopy('每节装箱数'),
                      hintText: context.toolsCopy('选填'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final c in cargoPalette)
                  InkWell(
                    onTap: () => setState(() => color = c),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(c),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: c == color
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.toolsCopy('取消')),
      ),
      FilledButton(onPressed: _save, child: Text(context.toolsCopy('保存规格'))),
    ],
  );
  void _save() {
    final dims = lengths.map((c) => double.tryParse(c.text)).toList();
    final kg = double.tryParse(weight.text);
    final qty = int.tryParse(quantity.text);
    if (name.text.trim().isEmpty ||
        dims.any((n) => n == null || !n.isFinite || n * _factor(unit) < 1) ||
        kg == null ||
        !kg.isFinite ||
        kg < 0 ||
        (quantity.text.trim().isNotEmpty && (qty == null || qty <= 0))) {
      setState(() => error = context.toolsCopy('请填写有效名称、正数尺寸和重量；每节装箱数可留空。'));
      return;
    }
    Navigator.pop(
      context,
      CargoPackageModel(
        id: widget.duplicate ? '' : widget.cargo?.id ?? '',
        name: name.text.trim(),
        type: type,
        dimensions: Dimensions3(
          (dims[0]! * _factor(unit)).round(),
          (dims[1]! * _factor(unit)).round(),
          (dims[2]! * _factor(unit)).round(),
        ),
        weightGrams: (kg * 1000).round(),
        colorValue: color,
        defaultSectionQuantity: qty,
      ),
    );
  }

  static int _factor(String u) => u == 'm'
      ? 1000
      : u == 'cm'
      ? 10
      : 1;
  static String _number(num n) =>
      n == n.round() ? '${n.round()}' : n.toString();
}

class ContainerPresetEditor extends StatefulWidget {
  const ContainerPresetEditor({this.preset, super.key});
  final ContainerPresetModel? preset;
  @override
  State<ContainerPresetEditor> createState() => _ContainerPresetEditorState();
}

class _ContainerPresetEditorState extends State<ContainerPresetEditor> {
  late final fields = [
    TextEditingController(text: widget.preset?.name ?? ''),
    TextEditingController(
      text: widget.preset?.dimensions.lengthMm.toString() ?? '',
    ),
    TextEditingController(
      text: widget.preset?.dimensions.widthMm.toString() ?? '',
    ),
    TextEditingController(
      text: widget.preset?.dimensions.heightMm.toString() ?? '',
    ),
    TextEditingController(
      text: widget.preset?.maxPayloadKg.toString() ?? '28000',
    ),
  ];
  String? error;
  @override
  void dispose() {
    for (final c in fields) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.preset == null
          ? context.toolsCopy('添加集装箱')
          : context.toolsCopy('编辑集装箱'),
    ),
    content: SizedBox(
      width: 390,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < fields.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: fields[i],
                  maxLength: i == 0 ? 80 : null,
                  keyboardType: i == 0
                      ? TextInputType.text
                      : TextInputType.number,
                  decoration: InputDecoration(
                    labelText: [
                      context.toolsCopy('名称'),
                      context.toolsCopy('内部长度'),
                      context.toolsCopy('内部宽度'),
                      context.toolsCopy('内部高度'),
                      context.toolsCopy('最大货重'),
                    ][i],
                    suffixText: i == 0
                        ? null
                        : i == 4
                        ? 'kg'
                        : 'mm',
                  ),
                ),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.toolsCopy('取消')),
      ),
      FilledButton(
        onPressed: () {
          final values = fields
              .skip(1)
              .map((c) => double.tryParse(c.text))
              .toList();
          if (fields.first.text.trim().isEmpty ||
              values.any((v) => v == null || !v.isFinite || v < 1)) {
            setState(() => error = context.toolsCopy('请填写名称及大于 0 的尺寸和载重'));
            return;
          }
          Navigator.pop(
            context,
            ContainerPresetModel(
              id: widget.preset?.id ?? const Uuid().v4(),
              name: fields.first.text.trim(),
              dimensions: Dimensions3(
                values[0]!.round(),
                values[1]!.round(),
                values[2]!.round(),
              ),
              maxPayloadGrams: (values[3]! * 1000).round(),
              colorValue: widget.preset?.colorValue ?? 0xFF718096,
              isBuiltIn: widget.preset?.isBuiltIn ?? false,
            ),
          );
        },
        child: Text(context.toolsCopy('保存')),
      ),
    ],
  );
}
