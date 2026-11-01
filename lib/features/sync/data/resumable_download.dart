import 'dart:convert';
import 'dart:io';

/// A partial is reusable only for the same origin, record and content identity.
Future<void> receiveResumableFile({
  required String destination,
  required String source,
  required Future<HttpClientResponse> Function(Map<String, String>) open,
  String? sha256,
  int? size,
  void Function(int, int)? onProgress,
}) async {
  if (size != null && (size < 0 || size > 2 * 1024 * 1024 * 1024)) {
    throw ArgumentError('文件超过下载大小限制');
  }
  final file = File(destination), marker = File('$destination.resume.json');
  final resumable = sha256 != null && size != null && size >= 0;
  final identity = jsonEncode([source, sha256, size]);
  await file.parent.create(recursive: true);
  var offset = 0;
  if (resumable && await file.exists() && await marker.exists()) {
    if (await marker.length() < 4096) {
      try {
        if (await marker.readAsString() == identity) {
          offset = await file.length();
        }
      } on FormatException {
        /* Incomplete markers restart this temporary file. */
      }
    }
  }
  if (size != null && offset > size) offset = 0;
  if (offset == 0) {
    await file.writeAsBytes(const []);
    if (resumable) await marker.writeAsString(identity, flush: true);
  }
  // The caller verifies the full digest, including a fully received interrupted file.
  if (resumable && offset == size) {
    onProgress?.call(offset, size);
    return;
  }
  final response = await open({
    if (offset > 0) HttpHeaders.rangeHeader: 'bytes=$offset-',
    if (offset > 0) HttpHeaders.ifRangeHeader: '"$sha256"',
    HttpHeaders.acceptEncodingHeader: 'identity',
  });
  if (response.statusCode != 200 && response.statusCode != 206) {
    await response.drain<void>();
    throw HttpException('文件下载失败 (${response.statusCode})');
  }
  if (response.statusCode == 206) {
    final range = RegExp(
      r'^bytes (\d+)-(\d+)/(\d+)$',
    ).firstMatch(response.headers.value(HttpHeaders.contentRangeHeader) ?? '');
    if (range == null ||
        int.parse(range[1]!) != offset ||
        int.parse(range[2]!) < offset ||
        int.parse(range[2]!) >= int.parse(range[3]!) ||
        (response.contentLength >= 0 &&
            response.contentLength != int.parse(range[2]!) - offset + 1) ||
        (size != null && int.parse(range[3]!) != size) ||
        (sha256 != null &&
            response.headers.value(HttpHeaders.etagHeader) != '"$sha256"')) {
      await response.drain<void>();
      await file.delete();
      if (await marker.exists()) await marker.delete();
      throw const FormatException('下载续传版本或偏移不匹配');
    }
  } else {
    // Old hosts and changed representations may correctly ignore Range.
    offset = 0;
  }
  final output = file.openWrite(
    mode: offset > 0 ? FileMode.append : FileMode.write,
  );
  var received = offset;
  Object? failure;
  StackTrace? failureStack;
  onProgress?.call(received, size ?? response.contentLength);
  try {
    await output.addStream(
      response.timeout(const Duration(seconds: 40)).map((chunk) {
        received += chunk.length;
        if (received > (size ?? 2 * 1024 * 1024 * 1024)) {
          throw const FormatException('下载内容超过预期大小');
        }
        onProgress?.call(received, size ?? response.contentLength);
        return chunk;
      }),
    );
    await output.flush();
    if (size != null && received != size) {
      throw const HttpException('文件下载中断，将从已接收位置继续');
    }
  } on Object catch (error, stack) {
    failure = error;
    failureStack = stack;
  } finally {
    try {
      await output.close();
    } on Object catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
    if (failure is FormatException) {
      if (await file.exists()) await file.delete();
      if (await marker.exists()) await marker.delete();
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
}
