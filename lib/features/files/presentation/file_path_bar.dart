import 'package:flutter/material.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/data/workspace_folder_repository.dart';

class FilePathBar extends StatefulWidget {
  const FilePathBar({
    required this.path,
    required this.onHome,
    required this.onFolder,
    this.collectionTitle,
    this.onBack,
    super.key,
  });
  final List<WorkspaceFolder> path;
  final String? collectionTitle;
  final VoidCallback onHome;
  final VoidCallback? onBack;
  final ValueChanged<String> onFolder;

  @override
  State<FilePathBar> createState() => _FilePathBarState();
}

class _FilePathBarState extends State<FilePathBar> {
  final scroll = ScrollController();
  void revealCurrent() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
    }
  });
  @override
  void initState() {
    super.initState();
    revealCurrent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.sizeOf(context);
    revealCurrent();
  }

  @override
  void didUpdateWidget(covariant FilePathBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    String signature(FilePathBar bar) =>
        '${bar.collectionTitle}|${bar.path.map((f) => '${f.id}:${f.name}').join('/')}';
    if (signature(oldWidget) != signature(widget)) revealCurrent();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('file-path-bar'),
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
    child: Row(
      children: [
        if (widget.onBack != null)
          IconButton(
            key: const ValueKey('mobile-files-back'),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
          ),
        TextButton.icon(
          key: const ValueKey('file-path-home'),
          onPressed: widget.onHome,
          icon: const Icon(Icons.home_outlined, size: 17),
          label: Text(context.l10n.t('filesHome')),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final folder in widget.path) ...[
                  const Text('/'),
                  Tooltip(
                    message: folder.name,
                    child: TextButton(
                      key: ValueKey('file-path-folder-${folder.id}'),
                      onPressed: () => widget.onFolder(folder.id),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          folder.name,
                          key:
                              widget.onBack != null &&
                                  folder.id == widget.path.last.id
                              ? const ValueKey('mobile-files-title')
                              : null,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
                if (widget.collectionTitle != null) ...[
                  const Text('/'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      widget.collectionTitle!,
                      key: widget.onBack != null
                          ? const ValueKey('mobile-files-title')
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
