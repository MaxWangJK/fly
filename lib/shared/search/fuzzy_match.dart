/// Case-insensitive search with conservative typo tolerance for names and
/// short labels. Every whitespace-separated query term must match somewhere.
abstract final class FuzzyMatch {
  static final _separators = RegExp(r'[\s\-_./\\,;:()\[\]{}]+');

  static String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool matches(String query, Iterable<String> fields) =>
      score(query, fields) != null;

  /// Exact and prefix matches outrank substring and typo-tolerant matches.
  /// Returns null for a non-match, including an empty query.
  static int? score(String query, Iterable<String> fields) {
    final terms = normalize(query).split(' ').where((term) => term.isNotEmpty);
    final values = fields.map(normalize).where((value) => value.isNotEmpty);
    final candidates = values.toList();
    if (terms.isEmpty || candidates.isEmpty) return null;
    var total = 0;
    for (final term in terms) {
      var best = 0;
      for (final value in candidates) {
        if (value == term) {
          best = 100;
          break;
        }
        if (value.startsWith(term)) {
          if (best < 80) best = 80;
        } else if (value.contains(term)) {
          if (best < 60) best = 60;
        } else if (term.length >= 3 && _typoMatch(term, value)) {
          if (best < 30) best = 30;
        }
      }
      if (best == 0) return null;
      total += best;
    }
    return total;
  }

  static bool _typoMatch(String term, String value) {
    final tolerance = term.length >= 5 ? 2 : 1;
    if (value.length <= 64 &&
        (value.length - term.length).abs() <= tolerance &&
        _withinDistance(term, value, tolerance)) {
      return true;
    }
    for (final word in value.split(_separators)) {
      if (word.isEmpty || word.length > 64) continue;
      // Compare whole words and prefixes. Do not fuzzy-match arbitrary parts
      // of a long field; that produces noisy results for short queries.
      if ((word.length - term.length).abs() <= tolerance &&
          _withinDistance(term, word, tolerance)) {
        return true;
      }
      if (word.length > term.length &&
          _withinDistance(term, word.substring(0, term.length), tolerance)) {
        return true;
      }
    }
    return false;
  }

  static bool _withinDistance(String left, String right, int limit) {
    if ((left.length - right.length).abs() > limit) return false;
    var previous = List<int>.generate(right.length + 1, (i) => i);
    var beforePrevious = previous;
    for (var i = 1; i <= left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0)..[0] = i;
      for (var j = 1; j <= right.length; j++) {
        var distance = left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1)
            ? previous[j - 1]
            : previous[j - 1] + 1;
        if (previous[j] + 1 < distance) distance = previous[j] + 1;
        if (current[j - 1] + 1 < distance) distance = current[j - 1] + 1;
        if (i > 1 &&
            j > 1 &&
            left.codeUnitAt(i - 1) == right.codeUnitAt(j - 2) &&
            left.codeUnitAt(i - 2) == right.codeUnitAt(j - 1) &&
            beforePrevious[j - 2] + 1 < distance) {
          distance = beforePrevious[j - 2] + 1;
        }
        current[j] = distance;
      }
      beforePrevious = previous;
      previous = current;
    }
    return previous[right.length] <= limit;
  }
}
