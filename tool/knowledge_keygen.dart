import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Run once per publisher. Never commit the generated private seed.
Future<void> main() async {
  final privateFile = File('license_tools/private/knowledge_signing.key');
  if (await privateFile.exists()) {
    stderr.writeln(
      'Knowledge signing seed already exists; refusing overwrite.',
    );
    exitCode = 1;
    return;
  }
  final random = Random.secure();
  final seed = List<int>.generate(32, (_) => random.nextInt(256));
  final pair = await Ed25519().newKeyPairFromSeed(seed);
  final publicKey = (await pair.extractPublicKey()).bytes;
  await privateFile.parent.create(recursive: true);
  await privateFile.writeAsString(base64UrlEncode(seed), flush: true);
  stdout.writeln('Public key: ${base64UrlEncode(publicKey)}');
  stdout.writeln(
    'Private signing seed saved under ignored license_tools/private/.',
  );
}
