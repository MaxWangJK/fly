import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/fly_localizations.dart';
import '../../../l10n/service_error_copy.dart';
import '../../../shared/attachments/attachment_storage.dart';
import 'media_viewer_actions.dart';

class VideoFileViewer extends StatefulWidget {
  const VideoFileViewer({
    required this.path,
    required this.name,
    this.controllerFactory,
    this.onExternal,
    this.onShare,
    super.key,
  });
  final String path, name;
  final VideoPlayerController Function(File)? controllerFactory;
  final Future<void> Function()? onExternal, onShare;
  @override
  State<VideoFileViewer> createState() => _VideoFileViewerState();
}

class _VideoFileViewerState extends State<VideoFileViewer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _loading = true, _fullscreen = false;
  String? _error;
  double? _dragPosition;
  double _audibleVolume = 1;
  int _generation = 0;
  String text(String zh, String en) => context.l10n.isZh ? zh : en;
  bool get _ready => _controller?.value.isInitialized == true && _error == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    final previous = _controller;
    _controller = null;
    previous?.removeListener(_changed);
    if (previous != null) unawaited(_release(previous));
    setState(() {
      _loading = true;
      _error = null;
      _dragPosition = null;
    });
    try {
      final file = File(widget.path);
      if (!await file.exists()) throw StateError('文件内容尚未下载，请检查同步状态');
      if (!mounted || generation != _generation) return;
      final controller =
          widget.controllerFactory?.call(file) ??
          VideoPlayerController.file(file);
      _controller = controller;
      controller.addListener(_changed);
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || generation != _generation) return;
      if (!controller.value.isInitialized ||
          controller.value.size.isEmpty ||
          controller.value.duration <= Duration.zero) {
        throw StateError('无法识别此视频的画面或时长，请检查文件或使用其他应用打开');
      }
      setState(() => _loading = false);
      // Start only on an explicit play action, including after resume.
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = context.flyError(error);
        });
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_controller?.value.hasError == true) {
        _loading = false;
        _error = text(
          '无法播放此视频，请检查文件完整性或使用其他应用打开。',
          'Unable to play this video. Check the file or open it in another app.',
        );
      }
    });
  }

  Future<void> _release(VideoPlayerController controller) async {
    try {
      await controller.dispose();
    } catch (_) {
      /* Native player already released. */
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.flyError(error))));
      }
    }
  }

  void _toggle() {
    if (!_ready) return;
    final controller = _controller!;
    unawaited(
      _run(() async {
        if (controller.value.isPlaying) {
          await controller.pause();
        } else {
          if (controller.value.isCompleted ||
              controller.value.position >= controller.value.duration) {
            await controller.seekTo(Duration.zero);
          }
          await controller.play();
        }
      }),
    );
  }

  void _seekBy(int seconds) {
    if (!_ready) return;
    final controller = _controller!;
    final value = (controller.value.position.inMilliseconds + seconds * 1000)
        .clamp(0, controller.value.duration.inMilliseconds);
    unawaited(_run(() => controller.seekTo(Duration(milliseconds: value))));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        _controller?.value.isInitialized == true) {
      final controller = _controller!;
      unawaited(_run(controller.pause));
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    controller?.removeListener(_changed);
    if (controller != null) unawaited(_release(controller));
    super.dispose();
  }

  String _time(Duration value) {
    final seconds = value.inSeconds;
    final hours = seconds ~/ 3600;
    return '${hours > 0 ? '$hours:' : ''}${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final value = _controller?.value;
    final duration = value?.duration ?? Duration.zero;
    final position = _dragPosition == null
        ? value?.position ?? Duration.zero
        : Duration(milliseconds: _dragPosition!.round());
    final content = PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && mounted) setState(() => _fullscreen = false);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _toggle,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _seekBy(-5),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _seekBy(5),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_fullscreen) {
              setState(() => _fullscreen = false);
            } else {
              Navigator.pop(context);
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Tooltip(
                message: widget.name,
                child: Text(
                  widget.name,
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
                    tooltip: text('分享', 'Share'),
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () => _run(
                      () =>
                          widget.onShare?.call() ??
                          shareViewerFile(button, widget.path, widget.name),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('video-open-external'),
                  tooltip: text('使用其他应用打开', 'Open in another app'),
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => _run(
                    () =>
                        widget.onExternal?.call() ??
                        PlatformAttachmentOpener().open(widget.path),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: ColoredBox(
                    color: Colors.black,
                    child: SizedBox.expand(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                key: ValueKey('video-loading'),
                              ),
                            )
                          : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _error!,
                                      key: const ValueKey('video-error'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      key: const ValueKey('video-retry'),
                                      onPressed: _initialize,
                                      icon: const Icon(Icons.refresh),
                                      label: Text(text('重试', 'Retry')),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Center(
                              child: AspectRatio(
                                aspectRatio: value!.aspectRatio > 0
                                    ? value.aspectRatio
                                    : 16 / 9,
                                child: VideoPlayer(_controller!),
                              ),
                            ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              _time(position),
                              key: const ValueKey('video-position'),
                            ),
                            Expanded(
                              child: Slider(
                                key: const ValueKey('video-seek'),
                                value: position.inMilliseconds.toDouble().clamp(
                                  0,
                                  math
                                      .max(1, duration.inMilliseconds)
                                      .toDouble(),
                                ),
                                max: math
                                    .max(1, duration.inMilliseconds)
                                    .toDouble(),
                                onChanged: !_ready
                                    ? null
                                    : (next) =>
                                          setState(() => _dragPosition = next),
                                onChangeEnd: !_ready
                                    ? null
                                    : (next) async {
                                        await _run(
                                          () => _controller!.seekTo(
                                            Duration(
                                              milliseconds: next.round(),
                                            ),
                                          ),
                                        );
                                        if (mounted) {
                                          setState(() => _dragPosition = null);
                                        }
                                      },
                              ),
                            ),
                            Text(_time(duration)),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              key: const ValueKey('video-play-pause'),
                              tooltip: text(
                                value?.isPlaying == true ? '暂停' : '播放',
                                value?.isPlaying == true ? 'Pause' : 'Play',
                              ),
                              onPressed: _ready ? _toggle : null,
                              icon: Icon(
                                value?.isPlaying == true
                                    ? Icons.pause
                                    : value?.isCompleted == true
                                    ? Icons.replay
                                    : Icons.play_arrow,
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('video-mute'),
                              tooltip: text(
                                (value?.volume ?? 1) == 0 ? '取消静音' : '静音',
                                (value?.volume ?? 1) == 0 ? 'Unmute' : 'Mute',
                              ),
                              onPressed: !_ready
                                  ? null
                                  : () => _run(() {
                                      if (_controller!.value.volume > 0) {
                                        _audibleVolume =
                                            _controller!.value.volume;
                                        return _controller!.setVolume(0);
                                      }
                                      return _controller!.setVolume(
                                        _audibleVolume,
                                      );
                                    }),
                              icon: Icon(
                                (value?.volume ?? 1) == 0
                                    ? Icons.volume_off
                                    : Icons.volume_up,
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                key: const ValueKey('video-volume'),
                                value: (value?.volume ?? 1).clamp(0, 1),
                                onChanged: !_ready
                                    ? null
                                    : (volume) => _run(() {
                                        if (volume > 0) _audibleVolume = volume;
                                        return _controller!.setVolume(volume);
                                      }),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('video-fullscreen'),
                              tooltip: text(
                                _fullscreen ? '退出全屏' : '全屏',
                                _fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                              ),
                              icon: Icon(
                                _fullscreen
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen,
                              ),
                              onPressed: () =>
                                  setState(() => _fullscreen = !_fullscreen),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (_fullscreen || viewport.width < 600) {
      return Dialog.fullscreen(
        key: const ValueKey('video-file-viewer'),
        child: content,
      );
    }
    return Dialog(
      key: const ValueKey('video-file-viewer'),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: math.min(1000, viewport.width - 48),
        height: math.min(700, viewport.height - 48),
        child: content,
      ),
    );
  }
}
