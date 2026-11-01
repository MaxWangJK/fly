import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/sync/domain/automatic_sync_merge.dart';

void main() {
  test('different daily review questions merge and intentional clear keeps other answers', () {
    final clocks = <String, dynamic>{
      'answers_json': [5000, 'home'],
      'answers_json/work': [1000, 'base'],
      'answers_json/home': [5000, 'home'],
    };
    final merged = mergeRecordFields(
      before: {'answers_json': '{"work":"base","home":"Home answer"}'},
      payload: {'answers_json': '{"work":"Work answer","home":""}'},
      fields: ['answers_json'],
      concurrentFields: {'answers_json'},
      clocks: clocks,
      incomingClocks: {
        'answers_json': [4000, 'work'],
        'answers_json/work': [4000, 'work'],
        'answers_json/home': [1000, 'base'],
      },
      mutationId: 'work',
      nowMilliseconds: 10000,
    );
    expect(jsonDecode(merged['answers_json'] as String), {
      'work': 'Work answer',
      'home': 'Home answer',
    });
    final cleared = mergeRecordFields(
      before: merged,
      payload: {'answers_json': '{"home":"Home answer"}'},
      fields: ['answers_json'],
      concurrentFields: {'answers_json'},
      clocks: clocks,
      incomingClocks: {
        'answers_json/work': [6000, 'clear'],
        'answers_json/home': [5000, 'home'],
      },
      mutationId: 'clear',
      nowMilliseconds: 10000,
    );
    expect(jsonDecode(cleared['answers_json'] as String), {
      'home': 'Home answer',
    });
  });
  test('concurrent field result is independent of delivery order and uses stable ties', () {
    for (final edits in [
      [(3000, 'a', 'old'), (5000, 'b', 'new')],
      [(5000, 'b', 'new'), (3000, 'a', 'old')],
      [(5000, 'a', 'old'), (5000, 'b', 'new')],
      [(5000, 'b', 'new'), (5000, 'a', 'old')],
    ]) {
      var data = <String, dynamic>{'phone': 'base', 'address': 'unchanged'};
      final clocks = <String, dynamic>{
        'phone': [1000, 'base'],
      };
      for (final edit in edits) {
        data = mergeRecordFields(
          before: data,
          payload: {'phone': edit.$3},
          fields: ['phone'],
          concurrentFields: {'phone'},
          clocks: clocks,
          incomingClocks: {
            'phone': [edit.$1, edit.$2],
          },
          mutationId: edit.$2,
          nowMilliseconds: 10000,
        );
      }
      expect(data, {'phone': 'new', 'address': 'unchanged'});
    }
  });
  test('explicit causal clear survives backwards clock and far future clocks are bounded', () {
    final clocks = <String, dynamic>{
      'phone': [5000, 'old'],
    };
    final cleared = mergeRecordFields(
      before: {'phone': 'value'},
      payload: {'phone': ''},
      fields: ['phone'],
      concurrentFields: {},
      clocks: clocks,
      incomingClocks: {
        'phone': [1000, 'new'],
      },
      mutationId: 'new',
      nowMilliseconds: 10000,
    );
    expect(cleared['phone'], '');
    expect((clocks['phone'] as List).first, 5001);
    mergeRecordFields(
      before: cleared,
      payload: {'phone': 'future'},
      fields: ['phone'],
      concurrentFields: {'phone'},
      clocks: clocks,
      incomingClocks: {
        'phone': [99999999999999, 'future'],
      },
      mutationId: 'future',
      nowMilliseconds: 10000,
    );
    expect((clocks['phone'] as List).first, 10000);
  });
  test('independent duplicate order and label IDs retain associations and fit field limits', () {
    final order = <String, dynamic>{
      'id': 'home',
      'order_number': 'ORD001',
      'customer_id': 'home-customer',
    };
    disambiguateSyncUniqueFields(
      'orders',
      '12345678-1234-1234-1234-123456789012',
      order,
      [
        {'id': 'work', 'order_number': 'ORD001'},
      ],
    );
    expect(order['order_number'], 'ORD001 (123456781234)');
    expect(order['customer_id'], 'home-customer');
    final name = 'x' * 80;
    final label = <String, dynamic>{
      'id': 'home',
      'scope': 'customer',
      'name': name,
    };
    disambiguateSyncUniqueFields(
      'tags',
      '12345678-1234-1234-1234-123456789012',
      label,
      [
        {'id': 'work', 'scope': 'customer', 'name': name},
      ],
    );
    expect((label['name'] as String).length, 80);
    final emoji = '🙂' * 40;
    final emojiLabel = <String, dynamic>{
      'id': 'home',
      'scope': 'customer',
      'name': emoji,
    };
    disambiguateSyncUniqueFields(
      'tags',
      '12345678-1234-1234-1234-123456789012',
      emojiLabel,
      [
        {'id': 'work', 'scope': 'customer', 'name': emoji},
      ],
    );
    expect((emojiLabel['name'] as String).length, lessThanOrEqualTo(80));
    expect(
      (emojiLabel['name'] as String).runes.any(
        (rune) => rune >= 0xd800 && rune <= 0xdfff,
      ),
      isFalse,
    );
    final customer = <String, dynamic>{'id': 'home', 'name': 'Same name'};
    disambiguateSyncUniqueFields(
      'customers',
      '12345678-1234-1234-1234-123456789012',
      customer,
      [
        {'id': 'work', 'name': 'Same name'},
      ],
    );
    expect(customer, {'id': 'home', 'name': 'Same name'});
  });
}
