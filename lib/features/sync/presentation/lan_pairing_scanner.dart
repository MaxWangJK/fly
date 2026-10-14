import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../l10n/fly_localizations.dart';
import '../domain/sync_protocol.dart';

class LanPairingScanner extends StatefulWidget {
  const LanPairingScanner({super.key});
  @override
  State<LanPairingScanner> createState() => _LanPairingScannerState();
}

class _LanPairingScannerState extends State<LanPairingScanner> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool detected = false;
  String? error;
  @override
  void dispose() {
    unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = context.l10n.isZh;
    return Scaffold(
      appBar: AppBar(title: Text(zh ? '扫描电脑二维码' : 'Scan desktop QR code')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: controller,
              errorBuilder: (_, _) => Center(
                child: Text(
                  zh ? '无法使用相机，请在系统设置中允许 Fly 使用相机后重试' : 'Camera unavailable. Allow camera access in system settings and try again.',
                ),
              ),
              onDetect: (capture) {
                if (detected) return;
                for (final barcode in capture.barcodes) {
                  final raw = barcode.rawValue;
                  if (raw == null) continue;
                  try {
                    LanPairingPayload.decode(raw);
                    detected = true;
                    Navigator.pop(context, raw);
                    return;
                  } on Object catch (e) {
                    final message = '$e'.replaceFirst('FormatException: ', '');
                    if (message != error) setState(() => error = message);
                  }
                }
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error ??
                    (zh
                        ? '电脑与手机连接同一网络，对准电脑端同步设置中的二维码。'
                        : 'Use the same network and scan the QR code in desktop sync settings.'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
