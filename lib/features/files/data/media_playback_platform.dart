import 'dart:io';

import 'package:fvp/fvp.dart' as fvp;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'video_cleanup_platform.dart';

/// Mobile keeps the standard platform player. Windows gets a decoder fallback
/// independent of optional Media Foundation codec installations.
void configureMediaPlayback() {
  if (Platform.isWindows) {
    fvp.registerWith(
      options: {
        'platforms': ['windows'],
        // The plugin defaults to forwarding every native diagnostic to Dart.
        // Keep warnings/errors without flooding the UI isolate during playback.
        'global': {'log': 'Warning', 'ffmpeg.log': 'warning'},
      },
    );
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'Windows media runtime (MDK, FFmpeg, libass)',
      ], await rootBundle.loadString('assets/licenses/windows-media.txt'));
    });
  }
  if (VideoPlayerPlatform.instance is! VideoCleanupPlatform) {
    VideoPlayerPlatform.instance = VideoCleanupPlatform(
      VideoPlayerPlatform.instance,
    );
  }
}
