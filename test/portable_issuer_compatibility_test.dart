import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly/shared/licensing/local_license_service.dart';

/// Fixtures are signed by the actual C# issuer with a throwaway TEST key.
/// No production signing key or real Windows machine identity is used.
class _MemoryLicenseStorage implements LicenseStorage {
  _MemoryLicenseStorage(this.rawMachine);

  final String rawMachine;
  String? value;

  @override
  Future<String> machineIdentity() async => rawMachine;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/portable_issuer_v1.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final now = DateTime.parse(fixture['nowUtc'] as String);

  LocalLicenseService service({
    _MemoryLicenseStorage? storage,
    DateTime? clock,
    String? publicKey,
  }) => LocalLicenseService(
    storage: storage ?? _MemoryLicenseStorage(fixture['rawMachine'] as String),
    publicKey: publicKey ?? fixture['publicKey'] as String,
    clock: () => clock ?? now,
  );

  Matcher failure(String key) =>
      isA<LicenseFailure>().having((error) => error.key, 'failure key', key);

  test('C# day token is accepted by the actual Fly verifier', () async {
    final storage = _MemoryLicenseStorage(fixture['rawMachine'] as String);
    final state = await service(storage: storage)
        .refresh(activation: fixture['timed'] as String);
    expect(state.allowed, isTrue);
    expect(state.isTrial, isFalse);
    expect(state.expiresAt, now.add(const Duration(days: 30)));
    expect(
      (jsonDecode(storage.value!) as Map<String, dynamic>)['license'],
      fixture['timed'],
    );
  });

  test('C# token survives a verifier restart', () async {
    final storage = _MemoryLicenseStorage(fixture['rawMachine'] as String);
    await service(storage: storage)
        .refresh(activation: fixture['timed'] as String);
    final state = await service(
      storage: storage,
      clock: now.add(const Duration(days: 10)),
    ).refresh();
    expect(state.allowed, isTrue);
    expect(state.isTrial, isFalse);
    expect(state.expiresAt, now.add(const Duration(days: 30)));
  });

  test('C# permanent token is accepted without a client update', () async {
    final state = await service(clock: DateTime.utc(2126, 10, 17))
        .refresh(activation: fixture['permanent'] as String);
    expect(state.allowed, isTrue);
    expect(state.isTrial, isFalse);
    expect(state.expiresAt, DateTime.utc(9999, 12, 31, 23, 59, 59));
  });

  test('expired C# token cannot reactivate a device', () async {
    await expectLater(
      service().refresh(activation: fixture['expired'] as String),
      throwsA(failure('licenseExpired')),
    );
  });

  test('C# token bound to another machine is rejected', () async {
    await expectLater(
      service().refresh(activation: fixture['wrongMachine'] as String),
      throwsA(failure('licenseMachineMismatch')),
    );
  });

  test('future-issued C# token is rejected', () async {
    await expectLater(
      service().refresh(activation: fixture['future'] as String),
      throwsA(failure('licenseInvalid')),
    );
  });

  test('altering the duration invalidates the C# signature', () async {
    final parts = (fixture['timed'] as String).split('.');
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
    ) as Map<String, dynamic>;
    payload['expiresAt'] = '9999-12-31T23:59:59Z';
    final altered =
        '${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.${parts[1]}';
    await expectLater(
      service().refresh(activation: altered),
      throwsA(failure('licenseInvalid')),
    );
  });

  test('an unrelated publisher cannot validate the C# token', () async {
    await expectLater(
      service(
        publicKey: base64Url.encode(List.filled(32, 0)).replaceAll('=', ''),
      ).refresh(activation: fixture['timed'] as String),
      throwsA(failure('licenseInvalid')),
    );
  });

  test('bad new activation preserves an existing C# activation', () async {
    final storage = _MemoryLicenseStorage(fixture['rawMachine'] as String);
    final verifier = service(storage: storage);
    await verifier.refresh(activation: fixture['timed'] as String);
    await expectLater(
      verifier.refresh(activation: fixture['wrongMachine'] as String),
      throwsA(failure('licenseMachineMismatch')),
    );
    expect(
      (jsonDecode(storage.value!) as Map<String, dynamic>)['license'],
      fixture['timed'],
    );
    expect((await verifier.refresh()).allowed, isTrue);
  });

  test('expiry does not silently grant a new trial', () async {
    final storage = _MemoryLicenseStorage(fixture['rawMachine'] as String);
    await service(storage: storage)
        .refresh(activation: fixture['timed'] as String);
    final state = await service(
      storage: storage,
      clock: now.add(const Duration(days: 31)),
    ).refresh();
    expect(state.allowed, isFalse);
  });

  test('malformed tokens never generate a valid C# activation', () async {
    for (final token in ['', 'not-a-token', 'a.b.c', 'a.b']) {
      await expectLater(
        service().refresh(activation: token),
        throwsA(failure('licenseInvalid')),
      );
    }
  });
}
