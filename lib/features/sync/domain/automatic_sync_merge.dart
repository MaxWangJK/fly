import 'dart:convert';

/// Field clocks travel with records across cloud and different LAN coordinators.
/// A clock is [UTC milliseconds, stable mutation ID]; it never uses arrival order
/// to break equal timestamps. Causal edits still supersede their observed base.
Map<String, dynamic> mergeRecordFields({
  required Map<String, dynamic> before,
  required Map<String, dynamic> payload,
  required List<String> fields,
  required Set<String> concurrentFields,
  required Map<String, dynamic> clocks,
  required Map<String, dynamic> incomingClocks,
  required String mutationId,
  required int nowMilliseconds,
}) {
  final data = {...before};
  List<dynamic> clock(dynamic raw, int fallback) {
    if (raw is List &&
        raw.length == 2 &&
        raw[0] is int &&
        raw[1] is String &&
        (raw[0] as int) >= 0 &&
        (raw[1] as String).length <= 80) {
      final time = raw[0] as int;
      return [time > nowMilliseconds + 300000 ? nowMilliseconds : time, raw[1]];
    }
    return [fallback, mutationId];
  }

  int compare(List<dynamic> a, List<dynamic> b) {
    final byTime = (a[0] as int).compareTo(b[0] as int);
    return byTime != 0 ? byTime : (a[1] as String).compareTo(b[1] as String);
  }

  for (final field in fields) {
    final prior = clock(clocks[field], 0);
    final next = clock(incomingClocks[field], nowMilliseconds);
    final concurrent = concurrentFields.contains(field);
    if (field == 'answers_json' && payload[field] is String) {
      try {
        final incoming = jsonDecode(payload[field] as String);
        final old = jsonDecode(before[field] as String? ?? '{}');
        if (incoming is Map && old is Map) {
          final answers = Map<String, dynamic>.from(old);
          for (final key in {...old.keys, ...incoming.keys}) {
            final child = 'answers_json/$key';
            if (!incoming.containsKey(key) &&
                !incomingClocks.containsKey(child)) {
              continue;
            }
            final oldClock = clock(clocks[child] ?? clocks[field], 0);
            final newClock = clock(
              incomingClocks[child] ?? incomingClocks[field],
              nowMilliseconds,
            );
            if (concurrent && compare(newClock, oldClock) < 0) continue;
            if (incoming.containsKey(key)) {
              answers[key as String] = incoming[key];
            } else {
              answers.remove(key);
            }
            if (!concurrent &&
                old[key] != incoming[key] &&
                (oldClock[0] as int) >= (newClock[0] as int)) {
              newClock[0] = (oldClock[0] as int) + 1;
            }
            clocks[child] = newClock;
          }
          data[field] = jsonEncode(answers);
          clocks[field] = compare(next, prior) >= 0 ? next : prior;
          continue;
        }
      } on FormatException {
        /* Legacy malformed text keeps the ordinary field rule. */
      }
    }
    if (before.containsKey(field) && concurrent && compare(next, prior) < 0) {
      continue;
    }
    data[field] = payload[field];
    if (!concurrent &&
        before[field] != payload[field] &&
        (prior[0] as int) >= (next[0] as int)) {
      next[0] = (prior[0] as int) + 1;
    }
    clocks[field] = next;
  }
  return data;
}

/// Keep independent records and relationships when two offline devices create
/// the same unique order number or label. Never merge people by display name.
void disambiguateSyncUniqueFields(
  String entity,
  String recordId,
  Map<String, dynamic> data,
  Iterable<Map<String, dynamic>> existing,
) {
  final fields = switch (entity) {
    'orders' => ['order_number'],
    'tags' => ['scope', 'name'],
    'file_tags' => ['normalized_name'],
    _ => <String>[],
  };
  if (fields.isEmpty || fields.any((f) => !data.containsKey(f))) return;
  final rows = existing.where((r) => r['id'] != data['id']).toList();
  bool collides() => rows.any((row) => fields.every((f) => row[f] == data[f]));
  if (!collides()) return;
  final field = fields.last, original = '${data[field]}';
  final suffix = recordId.replaceAll('-', '');
  var attempt = 0;
  do {
    final mark =
        ' (${suffix.substring(0, 12)}${attempt == 0 ? '' : '-$attempt'})';
    final limit =
        (entity == 'orders'
            ? 120
            : entity == 'file_tags'
            ? 100
            : 80) -
        mark.length;
    var cut = original.length > limit ? limit : original.length;
    if (cut > 0 &&
        cut < original.length &&
        original.codeUnitAt(cut - 1) >= 0xd800 &&
        original.codeUnitAt(cut - 1) <= 0xdbff) {
      cut--;
    }
    data[field] = '${original.substring(0, cut)}$mark';
    attempt++;
  } while (collides());
  if (entity == 'file_tags') data['name'] = data[field];
}
