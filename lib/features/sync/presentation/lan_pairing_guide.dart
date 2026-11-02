import 'package:flutter/material.dart';

import '../../../l10n/fly_localizations.dart';

/// An illustrated route to Fly's scanner; no camera permission or network work.
class LanPairingGuide extends StatefulWidget {
  const LanPairingGuide({super.key});

  @override
  State<LanPairingGuide> createState() => _LanPairingGuideState();
}

class _LanPairingGuideState extends State<LanPairingGuide>
    with SingleTickerProviderStateMixin {
  late final _scan = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _scan.stop();
      _scan.value = .5;
    } else if (!_scan.isAnimating && !_scan.isCompleted) {
      _scan.forward();
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = context.l10n.isZh;
    String t(String a, String b) => zh ? a : b;
    final colors = Theme.of(context).colorScheme;
    final steps = [
      t('在手机上打开 Fly', 'Open Fly on your phone'),
      t('我的 → 同步设置 → 本地同步', 'Me → Sync settings → Local sync'),
      t(
        '点击“扫描电脑二维码”，对准电脑屏幕',
        'Tap “Scan desktop QR code” and aim at the desktop screen',
      ),
    ];
    return Card.outlined(
      key: const ValueKey('lan-pairing-guide'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('用 Fly 内置扫一扫连接', 'Connect with Fly’s built-in scanner'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < steps.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${i + 1}. ',
                                style: TextStyle(color: colors.primary),
                              ),
                              Expanded(child: Text(steps[i])),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ExcludeSemantics(
                  child: Container(
                    key: const ValueKey('lan-guide-phone'),
                    width: 100,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(
                        color: colors.outlineVariant,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        Text(
                          t('手机 Fly', 'Phone Fly'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 64,
                          width: 64,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Icon(
                                  Icons.qr_code_scanner,
                                  size: 60,
                                  color: colors.primary,
                                ),
                              ),
                              AnimatedBuilder(
                                animation: _scan,
                                builder: (_, child) => Align(
                                  alignment: Alignment(
                                    0,
                                    _scan.value * 1.6 - .8,
                                  ),
                                  child: child,
                                ),
                                child: Container(
                                  key: const ValueKey('lan-guide-scan-line'),
                                  height: 2,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('操作示意', 'Illustration'),
                          style: Theme.of(context).textTheme.labelSmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              t(
                '此二维码需用 Fly 扫描，系统相机或其他应用无法完成配对。',
                'This code pairs devices inside Fly. The system camera and other apps cannot complete pairing.',
              ),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
