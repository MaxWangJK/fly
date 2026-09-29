import 'dart:io';

import 'package:flutter/services.dart';

/// Windows shell data object, not a text-only clipboard payload.
class PlatformFileTransfer {
  static const channel = MethodChannel('fly/file_transfer');
  Future<bool> copy(String path) async {
    if (!Platform.isWindows) throw UnsupportedError('当前平台请使用复制文件路径');
    return await channel.invokeMethod<bool>('copy', path) ?? false;
  }

  Future<bool> drag(String path) async {
    if (!Platform.isWindows) throw UnsupportedError('当前平台暂不支持原生拖出');
    return await channel.invokeMethod<bool>('drag', path) ?? false;
  }
}
