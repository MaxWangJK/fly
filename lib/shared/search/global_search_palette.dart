import 'dart:async';

import '../../config/feature_flags.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/fly_localizations.dart';
import '../../l10n/crm_copy.dart';

import '../../features/customers/presentation/customer_providers.dart';
import '../../features/orders/presentation/order_providers.dart';
import '../../features/tasks/presentation/task_providers.dart';
import '../design_system/design_tokens.dart';
import 'global_search_providers.dart';
import 'global_search_service.dart';

Future<void> showGlobalSearchPalette(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: Colors.black26,
  builder: (context) => const GlobalSearchPalette(),
);

class GlobalSearchPalette extends ConsumerStatefulWidget {
  const GlobalSearchPalette({super.key});

  @override
  ConsumerState<GlobalSearchPalette> createState() =>
      _GlobalSearchPaletteState();
}

class _GlobalSearchPaletteState extends ConsumerState<GlobalSearchPalette> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<FlySearchResult> _results = const [];
  int _selected = 0;
  bool _loading = false;
  String? _tag;
  Object? _error;
  int _request = 0;

  String _text(String key) =>
      FlyLocalizations(Localizations.localeOf(context)).t(key);

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final request = ++_request;
    setState(() {
      _loading = value.trim().isNotEmpty;
      _error = null;
      _results = [];
    });
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        final results = await ref
            .read(globalSearchServiceProvider)
            .search(
              value,
              translate: context.l10n.isZh
                  ? null
                  : (value) => crmEnglish[value] ?? value,
            );
        if (!mounted || request != _request) return;
        setState(() {
          _results = results;
          _selected = 0;
          _loading = false;
        });
      } catch (e) {
        if (mounted && request == _request) {
          setState(() {
            _error = e;
            _loading = false;
            _results = [];
          });
        }
      }
    });
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() => _selected = (_selected + delta) % _results.length);
    if (_selected < 0) setState(() => _selected = _results.length - 1);
  }

  void _open(FlySearchResult result) {
    if (result.type == SearchResultType.tag) {
      _openTag(result.entityId, label: result.title);
      return;
    }
    Navigator.pop(context);
    switch (result.type) {
      case SearchResultType.tag:
        break;
      case SearchResultType.file:
        context.go(
          Uri(
            path: '/files',
            queryParameters: {'id': result.entityId},
          ).toString(),
        );
      case SearchResultType.workspaceNote:
        context.go(
          Uri(
            path: enableKnowledgeHub ? '/knowledge' : '/notes',
            queryParameters: {
              if (enableKnowledgeHub) 'view': 'notes',
              'id': result.entityId,
            },
          ).toString(),
        );
      case SearchResultType.knowledge:
        context.go(
          Uri(
            path: '/knowledge',
            queryParameters: {'article': result.entityId},
          ).toString(),
        );
      case SearchResultType.customer:
        ref.read(selectedCustomerIdProvider.notifier).state = result.entityId;
        context.go('/customers/all');
      case SearchResultType.order:
        ref.read(selectedOrderIdProvider.notifier).state = result.entityId;
        context.go('/orders/all');
      case SearchResultType.task:
        ref.read(selectedTaskIdProvider.notifier).state = result.entityId;
        context.go('/tasks/today');
      case SearchResultType.note:
        ref.read(selectedCustomerIdProvider.notifier).state = result.entityId;
        ref.read(customerDetailExtensionProvider.notifier).state =
            DetailExtensionType.notes;
        context.go('/customers/all');
      case SearchResultType.followUp:
        ref.read(selectedCustomerIdProvider.notifier).state = result.entityId;
        ref.read(customerDetailExtensionProvider.notifier).state =
            DetailExtensionType.followUps;
        context.go('/customers/all');
    }
  }

  Future<void> _openTag(String name, {String? label}) async {
    _debounce?.cancel();
    final request = ++_request;
    _controller.clear();
    setState(() {
      _tag = label ?? name;
      _loading = true;
      _error = null;
      _results = [];
    });
    try {
      final results = await ref
          .read(globalSearchServiceProvider)
          .searchTag(name);
      if (!mounted || request != _request) return;
      setState(() {
        _results = results;
        _selected = 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    alignment: const Alignment(0, -.55),
    insetPadding: const EdgeInsets.symmetric(horizontal: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 570),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _move(1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _move(-1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter &&
              _results.isNotEmpty) {
            _open(_results[_selected]);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('global-search-input'),
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              readOnly: _tag != null,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: context.crmCopy('搜索 Fly…'),
                prefixIcon: Icon(Icons.search_rounded),
                suffixText: 'ESC',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 18),
              ),
            ),
            const Divider(height: 1),
            if (_tag != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: InputChip(
                    key: const ValueKey('search-tag-filter'),
                    label: Text('${_text('searchTag')}: $_tag'),
                    deleteButtonTooltipMessage: _text('clearTagFilter'),
                    onDeleted: () {
                      final name = _tag!;
                      setState(() => _tag = null);
                      _controller.text = name;
                      _search(name);
                      _focus.requestFocus();
                    },
                  ),
                ),
              ),
            Flexible(
              child: _error != null
                  ? TextButton(
                      onPressed: () => _tag == null
                          ? _search(_controller.text)
                          : _openTag(_tag!),
                      child: Text(_text('searchRetry')),
                    )
                  : _controller.text.trim().isEmpty && _tag == null
                  ? const _SearchHint()
                  : _loading
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : _results.isEmpty
                  ? Center(child: Text(context.crmCopy('没有匹配结果')))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        final previous = index == 0
                            ? null
                            : _results[index - 1].type;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (previous == null ||
                                _groupLabel(previous) !=
                                    _groupLabel(result.type))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  9,
                                  14,
                                  4,
                                ),
                                child: Text(
                                  result.type == SearchResultType.tag
                                      ? _text('searchTag')
                                      : result.type ==
                                            SearchResultType.knowledge
                                      ? context.l10n.t('knowledgeTitle')
                                      : context.crmCopy(
                                          _groupLabel(result.type),
                                        ),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ListTile(
                              key: ValueKey(
                                'search-${result.type.name}-${result.entityId}',
                              ),
                              selected: index == _selected,
                              dense: true,
                              leading: Icon(_icon(result.type), size: 18),
                              title: Text(result.title),
                              subtitle: Text(
                                result.type == SearchResultType.tag
                                    ? [
                                        for (final kind in [
                                          SearchResultType.customer,
                                          SearchResultType.order,
                                          SearchResultType.file,
                                          SearchResultType.workspaceNote,
                                        ])
                                          '${_text('searchCount_${kind.name}')} ${result.tagCounts[kind] ?? 0}',
                                      ].join(' · ')
                                    : _resultSubtitle(result),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _open(result),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(FlySpacing.xl),
    child: Text(
      context.crmCopy('客户、订单、任务、备注和跟进记录\n↑↓ 选择 · Enter 打开 · Esc 关闭'),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

String _groupLabel(SearchResultType type) => switch (type) {
  SearchResultType.tag => '标签',
  SearchResultType.file => '文件',
  SearchResultType.workspaceNote => '笔记',
  SearchResultType.knowledge => '资料库',
  SearchResultType.customer => '客户',
  SearchResultType.order => '订单',
  SearchResultType.task => '任务',
  SearchResultType.note => '备注 / 跟进',
  SearchResultType.followUp => '备注 / 跟进',
};

IconData _icon(SearchResultType type) => switch (type) {
  SearchResultType.tag => Icons.tag_outlined,
  SearchResultType.file => Icons.folder_outlined,
  SearchResultType.workspaceNote => Icons.article_outlined,
  SearchResultType.knowledge => Icons.menu_book_outlined,
  SearchResultType.customer => Icons.person_outline,
  SearchResultType.order => Icons.receipt_long_outlined,
  SearchResultType.task => Icons.check_box_outlined,
  SearchResultType.note => Icons.sticky_note_2_outlined,
  SearchResultType.followUp => Icons.forum_outlined,
};

String _resultSubtitle(FlySearchResult result) {
  final subtitle = result.subtitle.trim();
  final matched = result.matchedText.trim();
  final duplicate =
      matched.isEmpty ||
      result.title.toLowerCase() == matched.toLowerCase() ||
      subtitle.toLowerCase().contains(matched.toLowerCase());
  if (duplicate) return subtitle;
  return subtitle.isEmpty ? matched : '$subtitle · $matched';
}
