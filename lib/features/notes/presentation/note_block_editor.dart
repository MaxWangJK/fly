import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../domain/note_block.dart';
import '../../../l10n/fly_localizations.dart';

const noteBlockLabels = <NoteBlockType, String>{
  NoteBlockType.paragraph: '正文',
  NoteBlockType.heading1: '标题 1',
  NoteBlockType.heading2: '标题 2',
  NoteBlockType.heading3: '标题 3',
  NoteBlockType.bullet: '无序列表',
  NoteBlockType.numbered: '有序列表',
  NoteBlockType.checklist: '待办清单',
  NoteBlockType.quote: '引用',
  NoteBlockType.divider: '分割线',
  NoteBlockType.image: '图片',
  NoteBlockType.attachment: '附件',
  NoteBlockType.table: '表格',
  NoteBlockType.code: '代码',
};

/// Edits structured blocks; persistence and attachment imports belong to the host.
class NoteBlockEditor extends StatefulWidget {
  const NoteBlockEditor({
    required this.blocks,
    required this.onChanged,
    required this.onAddMedia,
    required this.mediaBuilder,
    this.onInsertMedia,
    super.key,
  });
  final List<NoteBlock> blocks;
  final ValueChanged<List<NoteBlock>> onChanged;
  final ValueChanged<NoteBlockType> onAddMedia;
  final void Function(NoteBlockType type, String blockId)? onInsertMedia;
  final Widget Function(BuildContext, NoteBlock) mediaBuilder;

  @override
  State<NoteBlockEditor> createState() => _NoteBlockEditorState();
}

class _NoteBlockEditorState extends State<NoteBlockEditor> {
  List<NoteBlock> get blocks => widget.blocks;
  ValueChanged<List<NoteBlock>> get onChanged => widget.onChanged;
  ValueChanged<NoteBlockType> get onAddMedia => widget.onAddMedia;
  void Function(NoteBlockType, String)? get onInsertMedia =>
      widget.onInsertMedia;
  Widget Function(BuildContext, NoteBlock) get mediaBuilder =>
      widget.mediaBuilder;
  final _focus = <String, FocusNode>{};
  String? _hovered;
  FocusNode _node(String id) => _focus.putIfAbsent(id, FocusNode.new);

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _split(String id, String value, TextSelection selection) {
    final index = blocks.indexWhere((b) => b.id == id);
    if (index < 0) return;
    final block = blocks[index];
    if (block.knownType == NoteBlockType.checklist && value.isEmpty) {
      update(
        index,
        NoteBlock(id: id, type: 'paragraph', content: {'text': ''}),
      );
      return;
    }
    final start = selection.isValid
        ? selection.start.clamp(0, value.length)
        : value.length;
    final end = selection.isValid
        ? selection.end.clamp(start, value.length)
        : value.length;
    final kind =
        [
          NoteBlockType.checklist,
          NoteBlockType.bullet,
          NoteBlockType.numbered,
        ].contains(block.knownType)
        ? block.knownType!
        : NoteBlockType.paragraph;
    final nextId = const Uuid().v7();
    final next = [...blocks];
    next[index] = NoteBlock(
      id: id,
      type: block.type,
      content: {...block.content, 'text': value.substring(0, start)},
    );
    next.insert(
      index + 1,
      NoteBlock(
        id: nextId,
        type: kind.name,
        content: {
          'text': value.substring(end),
          if (kind == NoteBlockType.checklist) 'checked': false,
        },
      ),
    );
    onChanged(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node(nextId).requestFocus();
    });
  }

  void update(int index, NoteBlock value) {
    final next = [...blocks];
    next[index] = value;
    onChanged(next);
  }

  void add(NoteBlockType type) {
    if (type == NoteBlockType.image || type == NoteBlockType.attachment) {
      onAddMedia(type);
      return;
    }
    final content = <String, dynamic>{
      if (type != NoteBlockType.divider && type != NoteBlockType.table)
        'text': '',
      if (type == NoteBlockType.checklist) 'checked': false,
      if (type == NoteBlockType.table)
        'rows': [
          ['', ''],
          ['', ''],
        ],
    };
    onChanged([
      ...blocks,
      NoteBlock(id: const Uuid().v7(), type: type.name, content: content),
    ]);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ReorderableListView.builder(
          key: const ValueKey('note-blocks'),
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: blocks.length,
          onReorderItem: (from, to) {
            final next = [...blocks];
            next.insert(to, next.removeAt(from));
            onChanged(next);
          },
          itemBuilder: (context, index) {
            final block = blocks[index];
            return MouseRegion(
              key: ValueKey(block.id),
              onEnter: (_) => setState(() => _hovered = block.id),
              onExit: (_) => setState(() => _hovered = null),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Opacity(
                      opacity: _hovered == block.id ? 1 : 0,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: context.l10n.t('blockAdd'),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add, size: 16),
                            onPressed: () => _split(
                              block.id,
                              block.text,
                              TextSelection.collapsed(
                                offset: block.text.length,
                              ),
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12, right: 4),
                              child: Tooltip(
                                message: context.l10n.t('blockDrag'),
                                child: const Icon(
                                  Icons.drag_indicator,
                                  size: 17,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _body(context, index, block)),
                    PopupMenuButton<String>(
                      tooltip: context.l10n.t('blockActions'),
                      icon: const Icon(Icons.more_horiz, size: 18),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'up',
                          child: Text(context.l10n.t('blockUp')),
                        ),
                        PopupMenuItem(
                          value: 'down',
                          child: Text(context.l10n.t('blockDown')),
                        ),
                        PopupMenuItem(
                          value: 'duplicate',
                          child: Text(context.l10n.t('blockDuplicate')),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(context.l10n.t('blockDelete')),
                        ),
                      ],
                      onSelected: (action) {
                        final next = [...blocks];
                        switch (action) {
                          case 'up':
                            if (index > 0) {
                              next.insert(index - 1, next.removeAt(index));
                            }
                          case 'down':
                            if (index < next.length - 1) {
                              next.insert(index + 1, next.removeAt(index));
                            }
                          case 'duplicate':
                            next.insert(
                              index + 1,
                              NoteBlock.encoded(
                                id: const Uuid().v7(),
                                type: block.type,
                                contentJson: block.contentJson,
                              ),
                            );
                          case 'delete':
                            next.removeAt(index);
                        }
                        onChanged(next);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      if (blocks.isEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<NoteBlockType>(
            tooltip: context.l10n.t('blockAdd'),
            itemBuilder: (_) => [
              for (final type in NoteBlockType.values)
                if (type != NoteBlockType.quote && type != NoteBlockType.code)
                  PopupMenuItem(
                    value: type,
                    child: Text(context.l10n.t('block_${type.name}')),
                  ),
            ],
            onSelected: add,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 18),
                  const SizedBox(width: 6),
                  Text(context.l10n.t('blockAdd')),
                ],
              ),
            ),
          ),
        ),
    ],
  );
  Widget _body(BuildContext context, int index, NoteBlock block) {
    final kind = block.knownType;
    if (kind == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('${context.l10n.t('blockUnsupported')}: ${block.type}'),
      );
    }
    if (kind == NoteBlockType.divider) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(),
      );
    }
    if (kind == NoteBlockType.image || kind == NoteBlockType.attachment) {
      return mediaBuilder(context, block);
    }
    if (kind == NoteBlockType.table) {
      return _TableBlock(block: block, onChanged: (b) => update(index, b));
    }
    final text = _BlockText(
      block: block,
      focusNode: _node(block.id),
      onSplit: (value, selection) => _split(block.id, value, selection),
      onChanged: (b) => update(index, b),
      onSlash: () async {
        final box = context.findRenderObject() as RenderBox;
        final point = box.localToGlobal(Offset.zero);
        final type = await showMenu<NoteBlockType>(
          context: context,
          position: RelativeRect.fromLTRB(point.dx + 30, point.dy + 40, 0, 0),
          items: [
            for (final type in NoteBlockType.values)
              if (type != NoteBlockType.quote && type != NoteBlockType.code)
                PopupMenuItem(
                  value: type,
                  child: Text(context.l10n.t('block_${type.name}')),
                ),
          ],
        );
        if (type == null || !context.mounted) return;
        if (type == NoteBlockType.image || type == NoteBlockType.attachment) {
          if (onInsertMedia != null) {
            onInsertMedia!(type, block.id);
            return;
          }
          update(
            index,
            NoteBlock(id: block.id, type: 'paragraph', content: {'text': ''}),
          );
          onAddMedia(type);
        } else {
          update(
            index,
            NoteBlock(
              id: block.id,
              type: type.name,
              content: {
                'text': '',
                if (type == NoteBlockType.checklist) 'checked': false,
                if (type == NoteBlockType.table)
                  'rows': [
                    ['', ''],
                    ['', ''],
                  ],
              },
            ),
          );
        }
      },
    );
    if (kind == NoteBlockType.checklist) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: block.content['checked'] == true,
            onChanged: (v) => update(
              index,
              NoteBlock(
                id: block.id,
                type: block.type,
                content: {...block.content, 'checked': v == true},
              ),
            ),
          ),
          Expanded(child: text),
        ],
      );
    }
    if (kind == NoteBlockType.bullet || kind == NoteBlockType.numbered) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 13, right: 8),
            child: kind == NoteBlockType.bullet
                ? const Icon(Icons.circle, size: 6)
                : Text('${_number(index)}.'),
          ),
          Expanded(child: text),
        ],
      );
    }
    if (kind == NoteBlockType.quote) {
      return Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 3,
            ),
          ),
        ),
        child: text,
      );
    }
    if (kind == NoteBlockType.code) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: text,
        ),
      );
    }
    return text;
  }

  int _number(int index) {
    var count = 1;
    for (
      var i = index - 1;
      i >= 0 && blocks[i].knownType == NoteBlockType.numbered;
      i--
    ) {
      count++;
    }
    return count;
  }
}

class _BlockText extends StatefulWidget {
  const _BlockText({
    required this.block,
    required this.onChanged,
    required this.onSlash,
    required this.focusNode,
    required this.onSplit,
  });
  final VoidCallback onSlash;
  final FocusNode focusNode;
  final void Function(String, TextSelection) onSplit;
  final NoteBlock block;
  final ValueChanged<NoteBlock> onChanged;
  @override
  State<_BlockText> createState() => _BlockTextState();
}

class _BlockTextState extends State<_BlockText> {
  late final controller = TextEditingController(text: widget.block.text);
  @override
  void didUpdateWidget(covariant _BlockText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.block.text) {
      controller.value = TextEditingValue(
        text: widget.block.text,
        selection: TextSelection.collapsed(offset: widget.block.text.length),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.block.knownType;
    final theme = Theme.of(context).textTheme;
    final style = switch (type) {
      NoteBlockType.heading1 => theme.headlineMedium?.copyWith(
        fontSize: 25,
        height: 1.4,
      ),
      NoteBlockType.heading2 => theme.headlineSmall?.copyWith(
        fontSize: 21,
        height: 1.4,
      ),
      NoteBlockType.heading3 => theme.titleLarge?.copyWith(
        fontSize: 18,
        height: 1.4,
      ),
      NoteBlockType.code => theme.bodyMedium?.copyWith(fontFamily: 'monospace'),
      _ => theme.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
    };
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
            !HardwareKeyboard.instance.isShiftPressed &&
            !controller.value.composing.isValid) {
          widget.onSplit(controller.text, controller.selection);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        key: ValueKey('block-text-${widget.block.id}'),
        focusNode: widget.focusNode,
        controller: controller,
        maxLines: null,
        style: style,
        decoration: InputDecoration(
          hintText: type == NoteBlockType.paragraph
              ? context.l10n.t('noteBlockHint')
              : context.l10n.t('block_${type?.name}'),
          border: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
        ),
        onChanged: (value) {
          final slash =
              type == NoteBlockType.paragraph &&
              widget.block.text.isEmpty &&
              value == '/';
          final shortcut = type == NoteBlockType.paragraph
              ? NoteBlock.shortcut(value)
              : null;
          final content = {
            ...widget.block.content,
            'text': shortcut == null ? value : '',
            if (shortcut == NoteBlockType.checklist) 'checked': false,
          };
          widget.onChanged(
            NoteBlock(
              id: widget.block.id,
              type: shortcut?.name ?? widget.block.type,
              content: content,
            ),
          );
          if (slash) widget.onSlash();
        },
      ),
    );
  }
}

class _TableBlock extends StatelessWidget {
  const _TableBlock({required this.block, required this.onChanged});
  final NoteBlock block;
  final ValueChanged<NoteBlock> onChanged;
  @override
  Widget build(BuildContext context) {
    final rows = (block.content['rows'] as List)
        .map((r) => (r as List).cast<String>().toList())
        .toList();
    void save() => onChanged(
      NoteBlock(
        id: block.id,
        type: block.type,
        content: {...block.content, 'rows': rows},
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: rows.first.length * 160.0,
            child: Table(
              border: TableBorder.all(color: Theme.of(context).dividerColor),
              children: [
                for (var r = 0; r < rows.length; r++)
                  TableRow(
                    children: [
                      for (var c = 0; c < rows[r].length; c++)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: TextFormField(
                            key: ValueKey('${block.id}-$r-$c'),
                            initialValue: rows[r][c],
                            maxLines: null,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              filled: false,
                            ),
                            onChanged: (value) {
                              rows[r][c] = value;
                              save();
                            },
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: rows.length >= 200
                  ? null
                  : () {
                      rows.add(List.filled(rows.first.length, ''));
                      save();
                    },
              child: Text(context.l10n.t('blockAddRow')),
            ),
            TextButton(
              onPressed: rows.first.length >= 30
                  ? null
                  : () {
                      for (final row in rows) {
                        row.add('');
                      }
                      save();
                    },
              child: Text(context.l10n.t('blockAddColumn')),
            ),
            TextButton(
              onPressed: rows.length <= 1
                  ? null
                  : () {
                      rows.removeLast();
                      save();
                    },
              child: Text(context.l10n.t('blockDeleteRow')),
            ),
            TextButton(
              onPressed: rows.first.length <= 1
                  ? null
                  : () {
                      for (final row in rows) {
                        row.removeLast();
                      }
                      save();
                    },
              child: Text(context.l10n.t('blockDeleteColumn')),
            ),
          ],
        ),
      ],
    );
  }
}
