import 'package:pasteboard/pasteboard.dart';

/// File paths only: text and unrelated clipboard contents are not imported.
class FileClipboard {
  Future<List<String>> readFiles() => Pasteboard.files();
}
