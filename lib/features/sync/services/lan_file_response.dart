import 'dart:io';
import 'dart:math';

Future<void> serveLanFile(HttpRequest request, File file, String hash) async {
  final response = request.response, size = await file.length();
  final etag = '"$hash"';
  response.headers
    ..contentType = ContentType.binary
    ..set(HttpHeaders.acceptRangesHeader, 'bytes')
    ..set(HttpHeaders.etagHeader, etag)
    ..set(HttpHeaders.cacheControlHeader, 'private, no-transform');
  var start = 0, end = size - 1;
  final range = request.headers.value(HttpHeaders.rangeHeader);
  final validator = request.headers.value(HttpHeaders.ifRangeHeader);
  if (range != null && (validator == null || validator == etag)) {
    final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    final from = match == null ? null : int.tryParse(match[1]!);
    final to = match == null || match[2]!.isEmpty
        ? end
        : int.tryParse(match[2]!);
    if (from == null || to == null || from >= size || to < from) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
      await response.close();
      return;
    }
    start = from;
    end = min(to, end);
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/$size',
    );
  }
  response.contentLength = end - start + 1;
  await response.addStream(file.openRead(start, end + 1));
  await response.close();
}
