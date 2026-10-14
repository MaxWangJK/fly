import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'design_tokens.dart';

bool isPhoneLayout(BuildContext context) =>
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) &&
    MediaQuery.sizeOf(context).shortestSide < 600;

bool useCompactLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final mobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return size.width < FlyBreakpoints.medium ||
      (mobile && size.shortestSide < 600);
}
