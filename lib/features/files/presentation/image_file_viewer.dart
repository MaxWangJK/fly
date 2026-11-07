import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../shared/attachments/attachment_storage.dart';
import '../../../l10n/service_error_copy.dart';
import 'media_viewer_actions.dart';

class ImageViewerItem {
  const ImageViewerItem({
    required this.id,
    required this.path,
    required this.name,
  });
  final String id, path, name;
}

class ImageFileViewer extends StatefulWidget {
  const ImageFileViewer({
    required this.path,
    required this.name,
    this.items = const [],
    this.initialIndex = 0,
    this.onChanged,
    this.onShare,
    this.onExternal,
    super.key,
  });
  final String path, name;
  final List<ImageViewerItem> items;
  final int initialIndex;
  final Future<void> Function(ImageViewerItem)? onChanged, onShare, onExternal;
  @override
  State<ImageFileViewer> createState() => _ImageFileViewerState();
}

class _ImageFileViewerState extends State<ImageFileViewer> {
  late final List<ImageViewerItem> _items;
  late final PageController _pages;
  late int _index;
  bool _zoomed = false;
  final _pageKeys = <int, GlobalKey<_ZoomImageState>>{};
  ImageViewerItem get _current => _items[_index];
  String text(String zh, String en) => context.l10n.isZh ? zh : en;

  @override
  void initState() {
    super.initState();
    _items = widget.items.isEmpty
        ? [
            ImageViewerItem(
              id: widget.path,
              path: widget.path,
              name: widget.name,
            ),
          ]
        : List.unmodifiable(widget.items);
    _index = widget.initialIndex.clamp(0, _items.length - 1);
    _pages = PageController(initialPage: _index);
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.flyError(error))));
      }
    }
  }

  void _go(int index) {
    if (index < 0 || index >= _items.length || index == _index) return;
    _pageKeys[_index]?.currentState?.reset();
    _pages.animateToPage(
      index,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    key: const ValueKey('image-file-viewer'),
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _go(_index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _go(_index + 1),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Tooltip(
              message: _current.name,
              child: Text(
                _current.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            leading: IconButton(
              tooltip: text('关闭', 'Close'),
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Builder(
                builder: (button) => IconButton(
                  key: const ValueKey('image-viewer-share'),
                  tooltip: text('分享', 'Share'),
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () => _action(
                    () =>
                        widget.onShare?.call(_current) ??
                        shareViewerFile(button, _current.path, _current.name),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: text('更多', 'More'),
                onSelected: (value) {
                  if (value == 'reset') {
                    _pageKeys[_index]?.currentState?.reset();
                  }
                  if (value == 'external') {
                    unawaited(
                      _action(
                        () =>
                            widget.onExternal?.call(_current) ??
                            PlatformAttachmentOpener().open(_current.path),
                      ),
                    );
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'reset',
                    child: Text(text('重置缩放', 'Reset zoom')),
                  ),
                  PopupMenuItem(
                    value: 'external',
                    child: Text(text('使用其他应用打开', 'Open in another app')),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  key: const ValueKey('image-viewer-pages'),
                  controller: _pages,
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: _items.length,
                  onPageChanged: (index) {
                    _pageKeys[_index]?.currentState?.reset();
                    setState(() {
                      _index = index;
                      _zoomed = false;
                    });
                    if (widget.onChanged != null) {
                      unawaited(_action(() => widget.onChanged!(_current)));
                    }
                  },
                  itemBuilder: (_, index) => _ZoomImage(
                    key: _pageKeys.putIfAbsent(
                      index,
                      () => GlobalKey<_ZoomImageState>(),
                    ),
                    item: _items[index],
                    onZoom: (zoomed) {
                      if (mounted && index == _index && zoomed != _zoomed) {
                        setState(() => _zoomed = zoomed);
                      }
                    },
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      key: const ValueKey('image-viewer-previous'),
                      tooltip: text('上一张', 'Previous image'),
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _index == 0 ? null : () => _go(_index - 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '${_index + 1} / ${_items.length}',
                        key: const ValueKey('image-viewer-counter'),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('image-viewer-next'),
                      tooltip: text('下一张', 'Next image'),
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _index == _items.length - 1
                          ? null
                          : () => _go(_index + 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ZoomImage extends StatefulWidget {
  const _ZoomImage({required this.item, required this.onZoom, super.key});
  final ImageViewerItem item;
  final ValueChanged<bool> onZoom;
  @override
  State<_ZoomImage> createState() => _ZoomImageState();
}

class _ZoomImageState extends State<_ZoomImage> {
  final _transform = TransformationController();
  Offset _doubleTap = Offset.zero;
  void reset() {
    _transform.value = Matrix4.identity();
    widget.onZoom(false);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onDoubleTapDown: (details) => _doubleTap = details.localPosition,
    onDoubleTap: () {
      if (_transform.value.getMaxScaleOnAxis() > 1.01) {
        reset();
        return;
      }
      _transform.value = Matrix4.identity()
        ..setEntry(0, 0, 2.5)
        ..setEntry(1, 1, 2.5)
        ..setEntry(0, 3, -_doubleTap.dx * 1.5)
        ..setEntry(1, 3, -_doubleTap.dy * 1.5);
      widget.onZoom(true);
    },
    child: InteractiveViewer(
      transformationController: _transform,
      minScale: 1,
      maxScale: 8,
      onInteractionEnd: (_) =>
          widget.onZoom(_transform.value.getMaxScaleOnAxis() > 1.01),
      child: SizedBox.expand(
        child: Center(
          child: Image.file(
            File(widget.item.path),
            key: ValueKey('viewer-image-${widget.item.id}'),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.l10n.t('fileImageUnavailable'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
