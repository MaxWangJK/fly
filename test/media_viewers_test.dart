import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/files/presentation/image_file_viewer.dart';
import 'package:fly/features/files/presentation/video_file_viewer.dart';
import 'package:fly/features/files/data/video_cleanup_platform.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player/video_player.dart';

import 'input_continuity_widget_test.dart' as ui;

class _Videos extends VideoPlayerPlatform {
  _Videos({this.emptyMetadata = false, this.creationGate, this.disposalGate});
  final bool emptyMetadata;
  final Completer<void>? creationGate, disposalGate;
  int created = 0, plays = 0, pauses = 0, disposed = 0;
  int surfaceBuilds = 0, unpausedDisposals = 0;
  final playing = <int, bool>{};
  double volume = 1;
  Duration position = Duration.zero;
  final events = <int, StreamController<VideoEvent>>{};
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    await creationGate?.future;
    final id = ++created;
    events[id] = StreamController.broadcast();
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) async* {
    yield VideoEvent(
      eventType: VideoEventType.initialized,
      duration: emptyMetadata ? Duration.zero : const Duration(seconds: 20),
      size: emptyMetadata ? Size.zero : const Size(640, 360),
    );
    yield* events[playerId]!.stream;
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) {
    surfaceBuilds++;
    return const ColoredBox(
      color: Color(0xFF355D53),
      child: Center(
        child: Icon(Icons.landscape, color: Colors.white, size: 72),
      ),
    );
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setVolume(int playerId, double value) async {
    volume = value;
  }

  @override
  Future<void> play(int playerId) async {
    plays++;
    playing[playerId] = true;
  }

  @override
  Future<void> pause(int playerId) async {
    pauses++;
    playing[playerId] = false;
  }

  @override
  Future<void> seekTo(int playerId, Duration value) async {
    position = value;
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;
  @override
  Future<void> dispose(int playerId) async {
    disposed++;
    if (playing.remove(playerId) == true) unpausedDisposals++;
    await disposalGate?.future;
    await events.remove(playerId)?.close();
  }
}

Future<void> _photo(File file, {bool portrait = false}) async {
  final size = portrait ? const Size(300, 480) : const Size(480, 300);
  final recorder = drawing.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFECE7DD), BlendMode.src);
  canvas.drawRect(
    Rect.fromLTWH(30, 25, size.width - 60, size.height - 50),
    Paint()..color = const Color(0xFF7D9F89),
  );
  for (var x = 45.0; x < size.width - 30; x += 30) {
    canvas.drawLine(
      Offset(x, 35),
      Offset(x, size.height - 35),
      Paint()
        ..color = const Color(0xFF355D53)
        ..strokeWidth = 5,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    final bytes = await image.toByteData(format: drawing.ImageByteFormat.png);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  testWidgets(
    'close during native creation cancels the initialization deadline and releases later',
    (tester) async {
      ui.viewport(tester, false);
      final original = VideoPlayerPlatform.instance;
      final gate = Completer<void>();
      final fake = _Videos(creationGate: gate);
      VideoPlayerPlatform.instance = VideoCleanupPlatform(fake);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-video-close-pending-'),
      ))!;
      try {
        await tester.runAsync(
          () => File('${root.path}/sample.mp4').writeAsBytes([1]),
        );
        await tester.pumpWidget(
          ui.app(
            VideoFileViewer(
              path: '${root.path}/sample.mp4',
              name: 'sample.mp4',
            ),
          ),
        );
        await ui.settle(tester);
        expect(find.byKey(const ValueKey('video-loading')), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        gate.complete();
        await ui.settle(tester);
        expect(fake.disposed, 1);
        expect(fake.unpausedDisposals, 0);
        expect(tester.takeException(), isNull);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await ui.settle(tester);
        VideoPlayerPlatform.instance = original;
        await tester.runAsync(() => root.delete(recursive: true));
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'playback failure releases immediately and retry waits for native disposal',
    (tester) async {
      ui.viewport(tester, false);
      final original = VideoPlayerPlatform.instance;
      final gate = Completer<void>();
      final fake = _Videos(disposalGate: gate);
      VideoPlayerPlatform.instance = VideoCleanupPlatform(fake);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-video-retry-release-'),
      ))!;
      try {
        await tester.runAsync(
          () => File('${root.path}/sample.mp4').writeAsBytes([1]),
        );
        await tester.pumpWidget(
          ui.app(
            VideoFileViewer(
              path: '${root.path}/sample.mp4',
              name: 'sample.mp4',
            ),
          ),
        );
        await ui.settle(tester);
        await tester.tap(find.byKey(const ValueKey('video-play-pause')));
        fake.events.values.single.addError(
          PlatformException(
            code: 'VideoError',
            message: 'Fixture decode failure',
          ),
        );
        await ui.settle(tester);
        expect(find.byKey(const ValueKey('video-error')), findsOneWidget);
        expect(fake.disposed, 1);
        expect(fake.unpausedDisposals, 0);
        await tester.tap(find.byKey(const ValueKey('video-retry')));
        await ui.settle(tester);
        expect(fake.created, 1);
        expect(find.byKey(const ValueKey('video-loading')), findsOneWidget);
        gate.complete();
        await ui.settle(tester);
        expect(fake.created, 2);
        expect(find.byKey(const ValueKey('video-error')), findsNothing);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await ui.settle(tester);
        VideoPlayerPlatform.instance = original;
        await tester.runAsync(() => root.delete(recursive: true));
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'video position updates retain the native surface and close pauses before disposal',
    (tester) async {
      ui.viewport(tester, false);
      final original = VideoPlayerPlatform.instance;
      final fake = _Videos();
      VideoPlayerPlatform.instance = VideoCleanupPlatform(fake);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-video-refresh-'),
      ))!;
      VideoPlayerController? controller;
      try {
        await tester.runAsync(
          () => File('${root.path}/sample.mp4').writeAsBytes([1]),
        );
        await tester.pumpWidget(
          ui.app(
            VideoFileViewer(
              path: '${root.path}/sample.mp4',
              name: 'sample.mp4',
              controllerFactory: (file) =>
                  controller = VideoPlayerController.file(file),
            ),
          ),
        );
        await ui.settle(tester);
        final surfaces = fake.surfaceBuilds;
        for (var i = 0; i < 100; i++) {
          controller!.value = controller!.value.copyWith(
            position: Duration(milliseconds: i * 10),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(
          fake.surfaceBuilds,
          surfaces,
          reason: 'Progress updates must not rebuild the video texture subtree',
        );
        await controller!.play();
        await tester.pumpWidget(const SizedBox.shrink());
        await ui.settle(tester);
        expect(fake.disposed, fake.created);
        expect(
          fake.unpausedDisposals,
          0,
          reason: 'Stop native decoding before asynchronous texture release',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await ui.settle(tester);
        VideoPlayerPlatform.instance = original;
        await tester.runAsync(() => root.delete(recursive: true));
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'zero video metadata is an error rather than a blank successful player',
    (tester) async {
      ui.viewport(tester, false);
      final original = VideoPlayerPlatform.instance;
      final fake = _Videos(emptyMetadata: true);
      VideoPlayerPlatform.instance = VideoCleanupPlatform(fake);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-video-empty-'),
      ))!;
      try {
        await tester.runAsync(
          () => File('${root.path}/sample.mp4').writeAsBytes([1]),
        );
        await tester.pumpWidget(
          ui.app(
            VideoFileViewer(
              path: '${root.path}/sample.mp4',
              name: 'sample.mp4',
            ),
          ),
        );
        await ui.settle(tester);
        expect(find.byKey(const ValueKey('video-error')), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('video-play-pause')),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await ui.settle(tester);
        VideoPlayerPlatform.instance = original;
        await tester.runAsync(() => root.delete(recursive: true));
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  for (final size in [
    const Size(1200, 850),
    const Size(390, 844),
    const Size(844, 390),
    const Size(320, 720),
  ]) {
    testWidgets(
      'image gallery switches, zooms, shares and preserves layout at $size',
      (tester) async {
        ui.viewport(tester, size.width < 900);
        tester.view.physicalSize = size;
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('fly-gallery-'),
        ))!;
        final boundary = GlobalKey();
        final shared = <String>[];
        try {
          await tester.runAsync(() async {
            await ui.fonts();
            await _photo(File('${root.path}/door.png'), portrait: true);
            await _photo(File('${root.path}/panels.png'));
          });
          final items = [
            ImageViewerItem(
              id: 'door',
              path: '${root.path}/door.png',
              name: '产品木门现场照片.png',
            ),
            ImageViewerItem(
              id: 'panels',
              path: '${root.path}/panels.png',
              name: '产品墙板展示.png',
            ),
            ImageViewerItem(
              id: 'missing',
              path: '${root.path}/not-downloaded.jpg',
              name: '待下载的现场图片.jpg',
            ),
          ];
          await tester.pumpWidget(
            ui.app(
              RepaintBoundary(
                key: boundary,
                child: ImageFileViewer(
                  path: items.first.path,
                  name: items.first.name,
                  items: items,
                  onShare: (item) async => shared.add(item.id),
                ),
              ),
              phone: size.width < 900,
            ),
          );
          await ui.settle(tester);
          expect(find.text('1 / 3'), findsOneWidget);
          expect(
            tester
                .widget<IconButton>(
                  find.byKey(const ValueKey('image-viewer-previous')),
                )
                .onPressed,
            isNull,
          );
          final image = find.byKey(const ValueKey('viewer-image-door'));
          await tester.tapAt(tester.getCenter(image));
          await tester.pump(const Duration(milliseconds: 80));
          await tester.tapAt(tester.getCenter(image));
          await ui.settle(tester);
          expect(
            tester
                .widget<PageView>(
                  find.byKey(const ValueKey('image-viewer-pages')),
                )
                .physics,
            isA<NeverScrollableScrollPhysics>(),
          );
          await tester.tap(find.byKey(const ValueKey('image-viewer-next')));
          await ui.settle(tester);
          expect(find.text('2 / 3'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('image-viewer-share')));
          await ui.settle(tester);
          expect(shared, ['panels']);
          await ui.capture(tester, boundary, 'gallery-${size.width.toInt()}');
          await tester.fling(
            find.byKey(const ValueKey('image-viewer-pages')),
            const Offset(-350, 0),
            1000,
          );
          await ui.settle(tester);
          expect(find.text('3 / 3'), findsOneWidget);
          expect(
            tester
                .widget<IconButton>(
                  find.byKey(const ValueKey('image-viewer-next')),
                )
                .onPressed,
            isNull,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('image-viewer-previous')));
          await ui.settle(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await ui.settle(tester);
          expect(find.text('1 / 3'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() => root.delete(recursive: true));
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
    testWidgets('video controls, lifecycle and cleanup at $size', (
      tester,
    ) async {
      ui.viewport(tester, size.width < 900);
      tester.view.physicalSize = size;
      final original = VideoPlayerPlatform.instance;
      final fake = _Videos();
      VideoPlayerPlatform.instance = VideoCleanupPlatform(fake);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-video-viewer-'),
      ))!;
      final boundary = GlobalKey();
      var external = 0;
      try {
        await tester.runAsync(() async {
          await ui.fonts();
          await File('${root.path}/sample.mp4').writeAsBytes([1]);
        });
        await tester.pumpWidget(
          ui.app(
            RepaintBoundary(
              key: boundary,
              child: VideoFileViewer(
                path: '${root.path}/sample.mp4',
                name: '产品安装演示.mp4',
                onExternal: () async {
                  external++;
                },
              ),
            ),
            phone: size.width < 900,
          ),
        );
        await ui.settle(tester);
        expect(find.byKey(const ValueKey('video-loading')), findsNothing);
        expect(fake.plays, 0);
        await tester.tap(find.byKey(const ValueKey('video-play-pause')));
        await ui.settle(tester);
        expect(fake.plays, 1);
        await tester.tap(find.byKey(const ValueKey('video-mute')));
        await ui.settle(tester);
        expect(fake.volume, 0);
        await tester.tap(find.byKey(const ValueKey('video-mute')));
        await ui.settle(tester);
        expect(fake.volume, 1);
        final slider = tester.widget<Slider>(
          find.byKey(const ValueKey('video-seek')),
        );
        slider.onChanged!(9000);
        await tester.pump();
        slider.onChangeEnd!(9000);
        await ui.settle(tester);
        expect(fake.position, const Duration(seconds: 9));
        await tester.tap(find.byKey(const ValueKey('video-fullscreen')));
        await ui.settle(tester);
        expect(
          tester
              .widget<Dialog>(find.byKey(const ValueKey('video-file-viewer')))
              .insetPadding,
          EdgeInsets.zero,
        );
        await ui.capture(tester, boundary, 'video-${size.width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('video-open-external')));
        await ui.settle(tester);
        expect(external, 1);
        final before = fake.pauses;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await ui.settle(tester);
        expect(fake.pauses, greaterThan(before));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await ui.settle(tester);
        expect(fake.plays, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await ui.settle(tester);
        expect(fake.disposed, fake.created);
        VideoPlayerPlatform.instance = original;
        await tester.runAsync(() => root.delete(recursive: true));
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets(
    'video error supports retry and external open, including missing files',
    (tester) async {
      ui.viewport(tester, true);
      final original = VideoPlayerPlatform.instance;
      final fake = _Videos();
      VideoPlayerPlatform.instance = VideoCleanupPlatform(fake);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fly-video-errors-'),
      ))!;
      try {
        await tester.runAsync(
          () => File('${root.path}/sample.mp4').writeAsBytes([1]),
        );
        await tester.pumpWidget(
          ui.app(
            VideoFileViewer(
              path: '${root.path}/sample.mp4',
              name: 'sample.mp4',
            ),
          ),
        );
        await ui.settle(tester);
        fake.events.values.single.addError(
          PlatformException(code: 'VideoError', message: 'Unsupported codec'),
        );
        await ui.settle(tester);
        expect(find.byKey(const ValueKey('video-error')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('video-retry')));
        await ui.settle(tester);
        expect(fake.created, 2);
        expect(find.byKey(const ValueKey('video-error')), findsNothing);
        await tester.pumpWidget(
          ui.app(
            VideoFileViewer(
              key: const ValueKey('missing'),
              path: '${root.path}/missing.mp4',
              name: 'missing.mp4',
            ),
          ),
        );
        await ui.settle(tester);
        expect(find.byKey(const ValueKey('video-error')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('video-open-external')),
          findsOneWidget,
        );
        expect(fake.created, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await ui.settle(tester);
        VideoPlayerPlatform.instance = original;
        await tester.runAsync(() => root.delete(recursive: true));
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
