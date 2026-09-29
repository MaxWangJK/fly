import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

class LicenseFailure implements Exception {
  const LicenseFailure(this.key);
  final String key;
}

abstract interface class LicenseStorage {
  Future<String> machineIdentity();
  Future<String?> read();
  Future<void> write(String value);
}

class WindowsLicenseStorage implements LicenseStorage {
  static const _channel = MethodChannel('fly/license_storage');
  @override
  Future<String> machineIdentity() async =>
      (await _channel.invokeMethod<String>('machine')) ?? '';
  @override
  Future<String?> read() => _channel.invokeMethod<String>('read');
  @override
  Future<void> write(String value) =>
      _channel.invokeMethod<void>('write', value);
}

class LocalLicenseState {
  const LocalLicenseState({
    required this.machineCode,
    required this.allowed,
    required this.expiresAt,
    required this.isTrial,
  });
  final String machineCode;
  final bool allowed;
  final DateTime expiresAt;
  final bool isTrial;
}

/// One owner serializes calls. No dependency on the business database.
class LocalLicenseService {
  LocalLicenseService({
    required this.storage,
    required this.publicKey,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final LicenseStorage storage;
  final String publicKey;
  final DateTime Function() clock;
  String machineCode = '';

  Future<DateTime> _verify(String token, DateTime now) async {
    try {
      if (token.length > 16384) throw const FormatException();
      final parts = token.split('.');
      if (parts.length != 2) throw const FormatException();
      final payload = base64Url.decode(base64Url.normalize(parts[0]));
      final signature = base64Url.decode(base64Url.normalize(parts[1]));
      final key = base64Url.decode(base64Url.normalize(publicKey));
      if (signature.length != 64 || key.length != 32) {
        throw const FormatException();
      }
      if (!await Ed25519().verify(
        payload,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
        ),
      )) {
        throw const LicenseFailure('licenseInvalid');
      }
      final json = jsonDecode(utf8.decode(payload));
      if (json is! Map<String, dynamic> ||
          json['licenseVersion'] != 1 ||
          json['machineCode'] is! String ||
          json['issuedAt'] is! String ||
          json['expiresAt'] is! String ||
          json['nonce'] is! String ||
          !RegExp(r'^[a-f0-9]{32,64}$').hasMatch(json['nonce'] as String)) {
        throw const FormatException();
      }
      if (json['machineCode'] != machineCode) {
        throw const LicenseFailure('licenseMachineMismatch');
      }
      final issued = DateTime.parse(json['issuedAt'] as String);
      final expiry = DateTime.parse(json['expiresAt'] as String);
      if (!issued.isUtc ||
          !expiry.isUtc ||
          !expiry.isAfter(issued) ||
          issued.isAfter(now.add(const Duration(minutes: 5)))) {
        throw const FormatException();
      }
      if (!expiry.isAfter(now)) throw const LicenseFailure('licenseExpired');
      return expiry;
    } on LicenseFailure {
      rethrow;
    } catch (_) {
      throw const LicenseFailure('licenseInvalid');
    }
  }

  Future<LocalLicenseState> refresh({String? activation}) async {
    if (activation != null && activation.trim().isEmpty) {
      throw const LicenseFailure('licenseInvalid');
    }
    try {
      final key = base64Url.decode(base64Url.normalize(publicKey));
      if (key.length != 32) throw const FormatException();
    } catch (_) {
      throw const LicenseFailure('licenseConfiguration');
    }
    if (machineCode.isEmpty) {
      final raw = (await storage.machineIdentity()).trim().toLowerCase();
      if (raw.isEmpty) throw const LicenseFailure('licenseStorageError');
      machineCode = hashes.sha256
          .convert(utf8.encode('fly:v1:$raw'))
          .toString()
          .toUpperCase();
    }
    final wallNow = clock().toUtc();
    final rawState = await storage.read();
    Map<String, dynamic> state;
    if (rawState == null) {
      state = {
        'version': 1,
        'machineCode': machineCode,
        'trialStartUtc': wallNow.toIso8601String(),
        'lastSeenUtc': wallNow.toIso8601String(),
      };
    } else {
      try {
        state = Map<String, dynamic>.from(jsonDecode(rawState) as Map);
        if (state['version'] != 1 || state['machineCode'] != machineCode) {
          throw const FormatException();
        }
      } catch (_) {
        throw const LicenseFailure('licenseStorageError');
      }
    }
    late DateTime start;
    late DateTime last;
    try {
      start = DateTime.parse(state['trialStartUtc'] as String);
      last = DateTime.parse(state['lastSeenUtc'] as String);
      if (!start.isUtc || !last.isUtc || last.isBefore(start)) {
        throw const FormatException();
      }
    } catch (_) {
      throw const LicenseFailure('licenseStorageError');
    }
    final now = wallNow.isAfter(last) ? wallNow : last;
    state['lastSeenUtc'] = now.toIso8601String();
    // Persist the high-water mark even when the supplied activation is invalid.
    await storage.write(jsonEncode(state));
    DateTime expiry = start.add(const Duration(days: 3));
    bool trial = true;
    final candidate = activation ?? state['license'] as String?;
    if (candidate != null && candidate.isNotEmpty) {
      try {
        expiry = await _verify(candidate, now);
        trial = false;
        if (activation != null) {
          state['license'] = candidate;
          await storage.write(jsonEncode(state));
        }
      } on LicenseFailure {
        if (activation != null) rethrow;
        // Invalid/expired stored licenses never create a new trial.
      }
    }
    return LocalLicenseState(
      machineCode: machineCode,
      allowed: expiry.isAfter(now),
      expiresAt: expiry,
      isTrial: trial,
    );
  }
}
