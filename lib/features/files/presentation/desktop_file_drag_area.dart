import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Require a deliberate mouse movement before handing a managed file to the OS.
/// Flutter's normal mouse pan threshold is only two logical pixels, which can
/// turn a slightly unsteady click into a drag back onto Fly's import surface.
class DesktopFileDragArea extends StatelessWidget {
  const DesktopFileDragArea({
    required this.onDragStart,
    required this.child,
    super.key,
  });

  final VoidCallback onDragStart;
  final Widget child;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      _FileDragRecognizer:
          GestureRecognizerFactoryWithHandlers<_FileDragRecognizer>(
            () => _FileDragRecognizer(debugOwner: this),
            (recognizer) => recognizer.onStart = (_) => onDragStart(),
          ),
    },
    child: child,
  );
}

class _FileDragRecognizer extends PanGestureRecognizer {
  _FileDragRecognizer({super.debugOwner})
    : super(
        supportedDevices: {PointerDeviceKind.mouse},
        allowedButtonsFilter: (buttons) => buttons == kPrimaryMouseButton,
      );

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved.abs() > 8;
}
