import '../../../l10n/service_error_copy.dart';
import '../../../l10n/fly_localizations.dart';

import 'package:flutter/material.dart';

import '../../../l10n/crm_copy.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/design_system/design_tokens.dart';
import '../../../shared/design_system/extension_panel.dart';
import '../../../shared/formatters/relative_date_formatter.dart';
import '../domain/customer.dart';
import 'customer_providers.dart';

class CustomerExtensionPanel extends ConsumerStatefulWidget {
  const CustomerExtensionPanel({
    required this.customerId,
    required this.type,
    required this.onClose,
    super.key,
  });

  final String customerId;
  final DetailExtensionType type;
  final VoidCallback onClose;

  @override
  ConsumerState<CustomerExtensionPanel> createState() =>
      _CustomerExtensionPanelState();
}

class _CustomerExtensionPanelState
    extends ConsumerState<CustomerExtensionPanel> {
  final _searchController = TextEditingController();
  final _inputController = TextEditingController();
  final _nextActionController = TextEditingController();
  final _inputFocus = FocusNode();
  final _nextActionFocus = FocusNode();
  String _search = '';
  String _channel = 'WhatsApp';
  NextActionType? _nextActionType;
  int _limit = 20;
  CustomerNote? _editingNote;
  CustomerFollowUp? _editingFollowUp;

  bool get _notes => widget.type == DetailExtensionType.notes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _inputFocus.requestFocus(),
    );
  }

  @override
  void didUpdateWidget(covariant CustomerExtensionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customerId != widget.customerId ||
        oldWidget.type != widget.type) {
      _searchController.clear();
      _inputController.clear();
      _nextActionController.clear();
      _editingNote = null;
      _editingFollowUp = null;
      _nextActionType = null;
      _search = '';
      _limit = 20;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _inputFocus.unfocus();
    _searchController.dispose();
    _inputController.dispose();
    _nextActionController.dispose();
    _inputFocus.dispose();
    _nextActionFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _inputController.text.trim();
    final nextAction = _nextActionController.text.trim();
    final repository = ref.read(customerRepositoryProvider);
    if (_notes) {
      if (content.isEmpty) return;
      final editing = _editingNote;
      if (editing == null) {
        await repository.addNote(widget.customerId, content: content);
      } else {
        await repository.saveNote(editing.copyWith(content: content));
      }
    } else {
      if (content.isEmpty && nextAction.isEmpty && _nextActionType == null) {
        return;
      }
      final editing = _editingFollowUp;
      if (editing == null) {
        await repository.addFollowUp(
          widget.customerId,
          channel: _channel,
          content: content,
          nextAction: nextAction,
          nextActionType: _nextActionType,
        );
      } else {
        await repository.saveFollowUp(
          editing.copyWith(
            channel: _channel,
            content: content,
            nextAction: nextAction,
            nextActionType: _nextActionType,
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _inputController.clear();
      _nextActionController.clear();
      _editingNote = null;
      _editingFollowUp = null;
      _nextActionType = null;
    });
    _inputFocus.requestFocus();
  }

  void _edit(CustomerNote note) {
    setState(() {
      _editingNote = note;
      _inputController.text = note.content;
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
    });
    _inputFocus.requestFocus();
  }

  void _editFollowUp(CustomerFollowUp followUp) {
    setState(() {
      _editingFollowUp = followUp;
      _channel = followUp.channel;
      _inputController.text = followUp.content;
      _nextActionController.text = followUp.nextAction;
      _nextActionType = followUp.nextActionType;
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
    });
    _inputFocus.requestFocus();
  }

  Future<void> _deleteFollowUp(CustomerFollowUp followUp) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.crmCopy('删除跟进记录')),
            content: Text(context.crmCopy('确定删除这条跟进记录？')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.crmCopy('取消')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: TextButton.styleFrom(foregroundColor: FlyColors.danger),
                child: Text(context.crmCopy('删除')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await ref.read(customerRepositoryProvider).softDeleteFollowUp(followUp.id);
    if (_editingFollowUp?.id == followUp.id && mounted) {
      setState(() {
        _editingFollowUp = null;
        _inputController.clear();
        _nextActionController.clear();
        _nextActionType = null;
      });
      _inputFocus.requestFocus();
    }
  }

  void _requestClose() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onClose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes
        ? ref.watch(
            customerNotesProvider((
              customerId: widget.customerId,
              search: _search,
              limit: _limit,
            )),
          )
        : null;
    final followUps = !_notes
        ? ref.watch(
            customerFollowUpSearchProvider((
              customerId: widget.customerId,
              search: _search,
              limit: _limit,
            )),
          )
        : null;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (_editingNote != null || _editingFollowUp != null) {
            setState(() {
              _editingNote = null;
              _editingFollowUp = null;
              _inputController.clear();
              _nextActionController.clear();
              _nextActionType = null;
            });
          } else {
            _requestClose();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        elevation: FlyElevation.popup,
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            FlyExtensionHeader(
              title: _notes ? context.crmCopy('客户备注') : context.crmCopy('跟进记录'),
              onClose: _requestClose,
              closeKey: const ValueKey('close-customer-extension'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                key: const ValueKey('extension-search'),
                controller: _searchController,
                onChanged: (value) => setState(() {
                  _search = value.trim();
                  _limit = 20;
                }),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _notes
                      ? context.crmCopy('搜索备注…')
                      : context.crmCopy('搜索内容或渠道…'),
                  prefixIcon: const Icon(Icons.search, size: 17),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                          icon: const Icon(Icons.close, size: 16),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 7, 8, 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(FlyRadius.md),
                ),
                child: Column(
                  children: [
                    FlySubmitOnEnter(
                      onSubmit: _submit,
                      child: TextField(
                        key: ValueKey(
                          _notes ? 'new-note-input' : 'new-followup-input',
                        ),
                        controller: _inputController,
                        focusNode: _inputFocus,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: _editingNote != null
                              ? context.crmCopy('编辑这条备注…')
                              : _editingFollowUp != null
                              ? context.crmCopy('编辑跟进内容…')
                              : _notes
                              ? context.crmCopy('记录客户信息…')
                              : context.crmCopy('记录本次跟进…'),
                        ),
                      ),
                    ),
                    if (!_notes) ...[
                      const Divider(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.flag_outlined, size: 15),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<NextActionType?>(
                                key: const ValueKey(
                                  'new-followup-next-action-type',
                                ),
                                value: _nextActionType,
                                isDense: true,
                                hint: Text(
                                  context.crmCopy('下一步类型（可选）'),
                                  style: TextStyle(fontSize: 12),
                                ),
                                items: [
                                  DropdownMenuItem<NextActionType?>(
                                    value: null,
                                    child: Text(context.crmCopy('不设置')),
                                  ),
                                  for (final type in NextActionType.values)
                                    DropdownMenuItem<NextActionType?>(
                                      value: type,
                                      child: Text(context.crmCopy(type.label)),
                                    ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _nextActionType = value),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                      FlySubmitOnEnter(
                        onSubmit: _submit,
                        child: TextField(
                          key: const ValueKey('new-followup-next-action'),
                          controller: _nextActionController,
                          focusNode: _nextActionFocus,
                          minLines: 1,
                          maxLines: 4,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            prefixIcon: Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                            ),
                            prefixIconConstraints: BoxConstraints(minWidth: 26),
                            hintText: context.crmCopy('下一步，例如：周五再次联系客户…'),
                          ),
                        ),
                      ),
                    ],
                    Row(
                      children: [
                        if (!_notes)
                          PopupMenuButton<String>(
                            tooltip: context.crmCopy('跟进渠道'),
                            initialValue: _channel,
                            onSelected: (value) =>
                                setState(() => _channel = value),
                            itemBuilder: (context) => [
                              for (final value in const [
                                'WhatsApp',
                                'Email',
                                'Call',
                                'Meeting',
                                'Facebook',
                                'Other',
                              ])
                                PopupMenuItem(value: value, child: Text(value)),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 5,
                              ),
                              child: Text(
                                _channel,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ),
                        if (_editingNote != null || _editingFollowUp != null)
                          TextButton(
                            onPressed: () => setState(() {
                              _editingNote = null;
                              _editingFollowUp = null;
                              _inputController.clear();
                              _nextActionController.clear();
                              _nextActionType = null;
                            }),
                            child: Text(context.crmCopy('取消编辑')),
                          ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.crmCopy('Enter 保存 · Shift+Enter 换行'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _notes
                  ? _NoteHistory(
                      value: notes!,
                      limit: _limit,
                      onLoadMore: () => setState(() => _limit += 20),
                      onEdit: _edit,
                      onDelete: (note) => ref
                          .read(customerRepositoryProvider)
                          .softDeleteNote(note.id),
                    )
                  : _FollowUpHistory(
                      value: followUps!,
                      limit: _limit,
                      onLoadMore: () => setState(() => _limit += 20),
                      onEdit: _editFollowUp,
                      onDelete: _deleteFollowUp,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteHistory extends StatelessWidget {
  const _NoteHistory({
    required this.value,
    required this.limit,
    required this.onLoadMore,
    required this.onEdit,
    required this.onDelete,
  });
  final AsyncValue<List<CustomerNote>> value;
  final int limit;
  final VoidCallback onLoadMore;
  final ValueChanged<CustomerNote> onEdit;
  final ValueChanged<CustomerNote> onDelete;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => Center(child: CircularProgressIndicator.adaptive()),
    error: (error, stack) => Center(
      child: Text(
        (context.l10n.isZh
            ? '备注读取失败：${context.flyError(error)}'
            : 'Unable to load notes: ${context.flyError(error)}'),
      ),
    ),
    data: (notes) => _HistoryList(
      emptyText: context.crmCopy('还没有备注，直接在上方连续记录客户信息。'),
      hasMore: notes.length >= limit,
      onLoadMore: onLoadMore,
      children: [
        for (final note in notes)
          GestureDetector(
            onDoubleTap: () => onEdit(note),
            child: FlyHistoryBlock(
              color: Color(note.colorValue),
              meta:
                  '${RelativeDateFormatter.dateTime(note.createdAt, isZh: context.l10n.isZh)}${note.updatedAt.difference(note.createdAt).inSeconds.abs() > 1 ? (context.l10n.isZh ? ' · 已编辑' : ' · Edited') : ''}',
              content: note.content,
              menu: PopupMenuButton<String>(
                tooltip: context.crmCopy('备注操作'),
                onSelected: (value) =>
                    value == 'edit' ? onEdit(note) : onDelete(note),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(context.crmCopy('编辑')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(context.crmCopy('删除')),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _FollowUpHistory extends StatelessWidget {
  const _FollowUpHistory({
    required this.value,
    required this.limit,
    required this.onLoadMore,
    required this.onEdit,
    required this.onDelete,
  });
  final AsyncValue<List<CustomerFollowUp>> value;
  final int limit;
  final VoidCallback onLoadMore;
  final ValueChanged<CustomerFollowUp> onEdit;
  final ValueChanged<CustomerFollowUp> onDelete;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => Center(child: CircularProgressIndicator.adaptive()),
    error: (error, stack) => Center(
      child: Text(
        (context.l10n.isZh
            ? '跟进记录读取失败：${context.flyError(error)}'
            : 'Unable to load follow-ups: ${context.flyError(error)}'),
      ),
    ),
    data: (followUps) => _HistoryList(
      emptyText: context.crmCopy('还没有跟进记录，直接在上方记录这次沟通。'),
      hasMore: followUps.length >= limit,
      onLoadMore: onLoadMore,
      children: [
        for (var index = 0; index < followUps.length; index++)
          Builder(
            builder: (context) {
              final followUp = followUps[index];
              Future<void> select(String value) async {
                if (value == 'edit') {
                  onEdit(followUp);
                } else {
                  onDelete(followUp);
                }
              }

              return GestureDetector(
                key: ValueKey('followup-${followUp.id}'),
                onSecondaryTapDown: (details) async {
                  final size = MediaQuery.sizeOf(context);
                  final value = await showMenu<String>(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      details.globalPosition.dx,
                      details.globalPosition.dy,
                      size.width - details.globalPosition.dx,
                      size.height - details.globalPosition.dy,
                    ),
                    items: [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(context.crmCopy('编辑')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(context.crmCopy('删除')),
                      ),
                    ],
                  );
                  if (value != null) await select(value);
                },
                child: FlyHistoryBlock(
                  color: const [
                    Color(0xFFE9EFFB),
                    Color(0xFFEAF4EF),
                    Color(0xFFF8F1E4),
                    Color(0xFFF0ECF8),
                  ][index % 4],
                  meta:
                      '${followUp.channel} · ${RelativeDateFormatter.dateTime(followUp.followedUpAt, isZh: context.l10n.isZh)}${followUp.updatedAt.difference(followUp.createdAt).inSeconds.abs() > 1 ? (context.l10n.isZh ? ' · 已编辑' : ' · Edited') : ''}',
                  content: followUp.content,
                  footer:
                      followUp.nextActionType == null &&
                          followUp.nextAction.isEmpty
                      ? null
                      : '下一步：${[if (followUp.nextActionType != null) followUp.nextActionType!.label, if (followUp.nextAction.isNotEmpty) followUp.nextAction].join(' · ')}',
                  menu: PopupMenuButton<String>(
                    tooltip: context.crmCopy('跟进操作'),
                    onSelected: select,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(context.crmCopy('编辑')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(context.crmCopy('删除')),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.emptyText,
    required this.hasMore,
    required this.onLoadMore,
    required this.children,
  });
  final String emptyText;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        ...children,
        if (hasMore)
          TextButton(
            onPressed: onLoadMore,
            child: Text(context.crmCopy('加载更多')),
          ),
      ],
    );
  }
}
