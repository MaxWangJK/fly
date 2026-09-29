import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

class FlyTagItem {
  const FlyTagItem({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  final String id;
  final String name;
  final int colorValue;
}

class FlyTagContainer extends StatelessWidget {
  const FlyTagContainer({
    required this.selected,
    required this.allTags,
    required this.onChanged,
    required this.onCreate,
    this.emptyHint = '点击添加标签',
    super.key,
  });

  final List<FlyTagItem> selected;
  final List<FlyTagItem> allTags;
  final Future<void> Function(Set<String> ids) onChanged;
  final Future<FlyTagItem> Function(String name) onCreate;
  final String emptyHint;

  Future<void> _openSelector(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .08),
      builder: (context) => _TagSelectorPopover(
        allTags: allTags,
        selectedIds: selected.map((tag) => tag.id).toSet(),
        onChanged: onChanged,
        onCreate: onCreate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(FlyRadius.md),
    child: InkWell(
      key: const ValueKey('tag-container'),
      onTap: () => _openSelector(context),
      borderRadius: BorderRadius.circular(FlyRadius.md),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(FlyRadius.md),
        ),
        child: selected.isEmpty
            ? Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  emptyHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in selected)
                    InputChip(
                      label: Text(
                        tag.name,
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Color(tag.colorValue)
                          .withValues(alpha: .16),
                      side: BorderSide.none,
                      onDeleted: () => onChanged(
                        selected
                            .where((item) => item.id != tag.id)
                            .map((item) => item.id)
                            .toSet(),
                      ),
                      onPressed: () => _openSelector(context),
                    ),
                ],
              ),
      ),
    ),
  );
}

class _TagSelectorPopover extends StatefulWidget {
  const _TagSelectorPopover({
    required this.allTags,
    required this.selectedIds,
    required this.onChanged,
    required this.onCreate,
  });

  final List<FlyTagItem> allTags;
  final Set<String> selectedIds;
  final Future<void> Function(Set<String> ids) onChanged;
  final Future<FlyTagItem> Function(String name) onCreate;

  @override
  State<_TagSelectorPopover> createState() => _TagSelectorPopoverState();
}

class _TagSelectorPopoverState extends State<_TagSelectorPopover> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late Set<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selectedIds};
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _toggle(String id) async {
    setState(
      () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
    );
    await widget.onChanged({..._selected});
  }

  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final existing = widget.allTags
        .where((tag) => tag.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    final tag = existing ?? await widget.onCreate(name);
    if (!_selected.contains(tag.id)) {
      setState(() => _selected.add(tag.id));
      await widget.onChanged({..._selected});
    }
    _controller.clear();
    setState(() => _search = '');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.allTags
        .where((tag) => tag.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    return Dialog(
      alignment: Alignment.centerRight,
      insetPadding: const EdgeInsets.only(right: 36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '选择标签',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter) {
                    _create();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: const ValueKey('tag-selector-search'),
                  controller: _controller,
                  focusNode: _focus,
                  onChanged: (value) => setState(() => _search = value.trim()),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 17),
                    hintText: '搜索；Enter 创建',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final tag in matches)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                        ),
                        value: _selected.contains(tag.id),
                        onChanged: (_) => _toggle(tag.id),
                        title: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: Color(tag.colorValue),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              tag.name,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    if (matches.isEmpty && _search.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '按 Enter 创建“$_search”',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
