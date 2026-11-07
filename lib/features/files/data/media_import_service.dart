import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'managed_file_storage.dart';

// dart:io XFile ignores its `name` argument. Keep the converted extension even
// when the compatible original lives at a differently named provider path.
class _NamedMediaFile extends XFile {
  _NamedMediaFile(super.path, this.name);
  @override
  final String name;
}

/// A scoped batch owns only its temporary conversion outputs, never the source.
class PreparedMedia {
  PreparedMedia(this.files, {this.release});
  final List<XFile> files;
  final Future<void> Function()? release;
  bool _released = false;
  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    await release?.call();
  }
}

class MediaImportService {
  MediaImportService({bool? ios, MethodChannel? channel})
    : ios = ios ?? Platform.isIOS,
      channel = channel ?? const MethodChannel('com.flyproduct.fly/media');
  final bool ios;
  final MethodChannel channel;
  static const _mediaExtensions = {
    '.heic',
    '.heif',
    '.hif',
    '.avif',
    '.jpg',
    '.jpeg',
    '.png',
    '.mov',
    '.mp4',
    '.m4v',
    '.3gp',
  };

  /// PHPicker preserves both resources of a Live Photo; a generic file picker
  /// can expose only the static part. Native outputs stay scoped to this batch.
  Future<PreparedMedia> pick() async {
    final response = await channel.invokeMapMethod<String, dynamic>('pick');
    if (response == null) return PreparedMedia(const []);
    final token = response['token'] as String;
    try {
      final paths = (response['files'] as List).cast<String>();
      return PreparedMedia(
        [for (final path in paths) _NamedMediaFile(path, p.basename(path))],
        release: () =>
            channel.invokeMethod<void>('releasePick', {'token': token}),
      );
    } catch (_) {
      await channel.invokeMethod<void>('releasePick', {'token': token});
      rethrow;
    }
  }

  Future<PreparedMedia> prepare(
    XFile input, {
    ImportCancellation? cancellation,
    void Function(double value)? progress,
  }) async {
    cancellation?.check();
    if (!ios ||
        !_mediaExtensions.contains(p.extension(input.name).toLowerCase())) {
      return PreparedMedia([input]);
    }
    final output = await Directory.systemTemp.createTemp('fly-media-');
    final id = const Uuid().v7();
    Timer? timer;
    bool polling = false;
    final removeCancel = cancellation?.onCancel(() {
      unawaited(
        channel.invokeMethod<void>('cancel', {'id': id}).catchError((_) {}),
      );
    });
    try {
      cancellation?.check();
      timer = Timer.periodic(const Duration(milliseconds: 350), (_) async {
        if (polling) return;
        polling = true;
        try {
          final value = await channel.invokeMethod<double>('progress', {
            'id': id,
          });
          if (timer?.isActive == true && value != null) progress?.call(value);
        } on PlatformException {
          // Progress is optional; conversion errors are returned by normalize.
        } on MissingPluginException {
          // Test/older native bridges may omit progress reporting.
        } finally {
          polling = false;
        }
      });
      final result = await channel.invokeMapMethod<String, dynamic>(
        'normalize',
        {
          'id': id,
          'source': input.path,
          'name': input.name,
          'output': output.path,
        },
      );
      cancellation?.check();
      final path = result?['path'] as String?;
      final name = result?['name'] as String?;
      if (path == null || name == null) throw StateError('媒体转换没有返回可用文件');
      // Returning the original is allowed for already compatible media.
      if (p.normalize(path) != p.normalize(input.path) &&
          !p.isWithin(output.path, path)) {
        throw StateError('媒体转换返回了无效路径');
      }
      if (!await File(path).exists() || await File(path).length() == 0) {
        throw StateError('媒体转换输出为空，请重试');
      }
      progress?.call(1);
      return PreparedMedia(
        [_NamedMediaFile(path, p.basename(name))],
        release: () async {
          if (await output.exists()) await output.delete(recursive: true);
        },
      );
    } on PlatformException catch (error) {
      if (await output.exists()) await output.delete(recursive: true);
      if (error.code == 'CANCELLED') throw ImportCancelled();
      throw StateError(error.message ?? '媒体格式转换失败，请重试');
    } catch (_) {
      if (await output.exists()) await output.delete(recursive: true);
      rethrow;
    } finally {
      timer?.cancel();
      removeCancel?.call();
    }
  }
}
