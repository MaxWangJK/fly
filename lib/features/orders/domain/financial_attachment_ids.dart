import 'dart:convert';

/// Keeps existing single-file records readable without a database migration.
/// Multiple IDs travel in the existing opaque text field as a JSON array.
abstract final class FinancialAttachmentIds {
  static List<String> decode(String? value) {
    if (value == null || value.isEmpty) return const [];
    if (!value.startsWith('[')) return [value];
    try {
      final decoded = jsonDecode(value);
      if (decoded is List && decoded.every((id) => id is String)) {
        return List<String>.unmodifiable(decoded.cast<String>().toSet());
      }
    } on FormatException {
      // Preserve an unrecognized legacy value rather than losing its reference.
    }
    return [value];
  }

  static String? encode(Iterable<String> ids) {
    final values = ids.toSet().toList();
    return switch (values.length) {
      0 => null,
      1 => values.single,
      _ => jsonEncode(values),
    };
  }
}
