import 'package:flutter/material.dart';

/// Shared phone search and creation controls, above the primary navigation.
class MobileWorkspaceActions extends StatefulWidget {
  const MobileWorkspaceActions({
    required this.child,
    required this.searchHint,
    required this.query,
    required this.onSearchChanged,
    required this.actionId,
    this.onAdd,
    this.addLabel,
    this.showSearchButton = true,
    super.key,
  });

  final Widget child;
  final String searchHint, query, actionId;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onAdd;
  final String? addLabel;
  final bool showSearchButton;

  @override
  State<MobileWorkspaceActions> createState() => _MobileWorkspaceActionsState();
}

class _MobileWorkspaceActionsState extends State<MobileWorkspaceActions> {
  late final controller = TextEditingController(text: widget.query);
  final focus = FocusNode();
  bool searching = false;

  @override
  void didUpdateWidget(covariant MobileWorkspaceActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.query) controller.text = widget.query;
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  void openSearch() {
    setState(() => searching = true);
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (searching)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            key: ValueKey('${widget.actionId}-search-input'),
            controller: controller,
            focusNode: focus,
            textInputAction: TextInputAction.search,
            onChanged: widget.onSearchChanged,
            onSubmitted: (_) => focus.unfocus(),
            decoration: InputDecoration(
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: Localizations.localeOf(context).languageCode == 'zh'
                    ? '关闭搜索'
                    : 'Close search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  widget.onSearchChanged('');
                  focus.unfocus();
                  setState(() => searching = false);
                },
              ),
            ),
          ),
        ),
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(child: widget.child),
            if (MediaQuery.viewInsetsOf(context).bottom == 0)
              Positioned(
                right: 16,
                bottom:
                    MediaQuery.orientationOf(context) == Orientation.portrait
                    ? 36
                    : 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.showSearchButton)
                      FloatingActionButton(
                        key: ValueKey('${widget.actionId}-search-button'),
                        heroTag: '${widget.actionId}-search',
                        tooltip: widget.searchHint,
                        elevation: 0,
                        shape: const CircleBorder(),
                        onPressed: openSearch,
                        child: const Icon(Icons.search),
                      ),
                    if (widget.onAdd != null) ...[
                      if (widget.showSearchButton) const SizedBox(height: 12),
                      FloatingActionButton(
                        key: ValueKey('${widget.actionId}-add-button'),
                        heroTag: '${widget.actionId}-add',
                        tooltip: widget.addLabel,
                        elevation: 0,
                        shape: const CircleBorder(),
                        onPressed: widget.onAdd,
                        child: const Icon(Icons.add),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
