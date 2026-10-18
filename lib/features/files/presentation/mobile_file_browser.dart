import 'package:flutter/material.dart';

class MobileFileFolder {
  const MobileFileFolder({
    required this.id,
    required this.name,
    required this.onOpen,
    required this.onLongPress,
    this.icon = Icons.folder_rounded,
    this.subtitle,
  });

  final String id, name;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onOpen, onLongPress;
}

class MobileFilesHeader extends StatefulWidget {
  const MobileFilesHeader({
    required this.query,
    required this.searchHint,
    required this.onSearch,
    required this.menu,
    this.title,
    this.onBack,
    super.key,
  });

  final String query, searchHint;
  final String? title;
  final ValueChanged<String> onSearch;
  final VoidCallback? onBack;
  final Widget menu;

  @override
  State<MobileFilesHeader> createState() => _MobileFilesHeaderState();
}

class _MobileFilesHeaderState extends State<MobileFilesHeader> {
  late final controller = TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(covariant MobileFilesHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.query) controller.text = widget.query;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
    child: Column(
      children: [
        if (widget.title != null)
          Row(
            children: [
              IconButton(
                key: const ValueKey('mobile-files-back'),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  widget.title!,
                  key: const ValueKey('mobile-files-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              widget.menu,
            ],
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('file-search-input'),
                controller: controller,
                onChanged: widget.onSearch,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: widget.query.isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey('files-search-clear'),
                          tooltip: MaterialLocalizations.of(context)
                              .deleteButtonTooltip,
                          onPressed: () => widget.onSearch(''),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            if (widget.title == null) widget.menu else const SizedBox(width: 8),
          ],
        ),
      ],
    ),
  );
}

class MobileFileFoldersSliver extends StatelessWidget {
  const MobileFileFoldersSliver({
    required this.folders,
    required this.list,
    super.key,
  });

  final List<MobileFileFolder> folders;
  final bool list;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget item(MobileFileFolder folder) {
      if (list) {
        return ListTile(
          key: ValueKey('mobile-file-folder-${folder.id}'),
          leading: Icon(folder.icon, color: colors.primary, size: 36),
          title: Text(folder.name),
          subtitle: folder.subtitle == null ? null : Text(folder.subtitle!),
          trailing: const Icon(Icons.chevron_right),
          onTap: folder.onOpen,
          onLongPress: folder.onLongPress,
        );
      }
      return Material(
        key: ValueKey('mobile-file-folder-${folder.id}'),
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: folder.onOpen,
          onLongPress: folder.onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(folder.icon, color: colors.primary, size: 54),
                const SizedBox(height: 8),
                Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (folder.subtitle != null)
                  Text(
                    folder.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      sliver: list
          ? SliverList.builder(
              itemCount: folders.length,
              itemBuilder: (_, index) => item(folders[index]),
            )
          : SliverLayoutBuilder(
              builder: (context, constraints) => SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: (constraints.crossAxisExtent / 108)
                      .floor()
                      .clamp(2, 6),
                  mainAxisExtent:
                      122 + MediaQuery.textScalerOf(context).scale(28) - 28,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 4,
                ),
                itemCount: folders.length,
                itemBuilder: (_, index) => item(folders[index]),
              ),
            ),
    );
  }
}
