import 'dart:io';

import 'package:fvp/fvp.dart' as fvp;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Mobile keeps the standard platform player. Windows gets a decoder fallback
/// independent of optional Media Foundation codec installations.
void configureMediaPlayback() {
  if (Platform.isWindows) {
    fvp.registerWith(
      options: {
        'platforms': ['windows'],
      },
    );
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'Windows media runtime (MDK, FFmpeg, libass)',
      ], await rootBundle.loadString('assets/licenses/windows-media.txt'));
    });
  }
}
