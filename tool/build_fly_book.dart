import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import 'package:fly/features/knowledge/data/fly_book_codec.dart';
import 'package:fly/features/knowledge/domain/fly_book.dart';

/// Publisher-only sources and private keys are never Flutter assets.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/build_fly_book.dart SOURCE_DIRECTORY OUTPUT.fly',
    );
    exitCode = 1;
    return;
  }
  final source = p.normalize(p.absolute(args[0]));
  String inside(String relative) {
    if (relative.contains('..') ||
        p.isAbsolute(relative) ||
        relative.contains('\\') ||
        !RegExp(r'^[a-zA-Z0-9_/.-]+$').hasMatch(relative)) {
      throw const FormatException('Unsafe publisher source path');
    }
    final path = p.normalize(p.join(source, relative));
    if (!p.isWithin(source, path)) {
      throw const FormatException('Source escaped book directory');
    }
    return path;
  }

  final data = jsonDecode(
    await File(p.join(source, 'book.json')).readAsString(),
  ) as Map<String, dynamic>;
  final assets = <String, Uint8List>{};
  await for (final entity in Directory(
    p.join(source, 'assets'),
  ).list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = p.relative(entity.path, from: source).replaceAll('\\', '/');
    if (!FlyBook.validAssetPath(path)) {
      throw const FormatException('Unsupported publisher image');
    }
    assets[path] = await entity.readAsBytes();
  }
  final chapters = <FlyBookChapter>[];
  for (final chapter
      in (data['chapters'] as List).cast<Map<String, dynamic>>()) {
    chapters.add(
      FlyBookChapter(
        id: chapter['id'] as String,
        title: chapter['title'] as String,
        html: await File(inside(chapter['file'] as String)).readAsString(),
      ),
    );
  }
  final book = FlyBook(
    id: data['id'] as String,
    title: data['title'] as String,
    version: data['version'] as int,
    author: data['author'] as String,
    description: data['description'] as String,
    css: await File(inside(data['stylesheet'] as String)).readAsString(),
    chapters: chapters,
    assets: assets,
  );
  final seedFile = File('license_tools/private/knowledge_signing.key');
  if (!await seedFile.exists()) {
    throw StateError(
      'Publisher signing seed is missing; restore it instead of replacing it.',
    );
  }
  final seed = _privateKey(await seedFile.readAsString());
  final pair = await Ed25519().newKeyPairFromSeed(seed);
  final publicKey = (await pair.extractPublicKey()).bytes;
  final definesFile = File('license_tools/private/book_build_defines.json');
  Map<String, dynamic> defines;
  if (await definesFile.exists()) {
    try {
      defines =
          jsonDecode(await definesFile.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      throw StateError(
        'Private reader configuration is invalid. Its contents are not logged.',
      );
    } on TypeError {
      throw StateError(
        'Private reader configuration has an invalid structure.',
      );
    }
    if (defines['KNOWLEDGE_PUBLIC_KEY'] != base64UrlEncode(publicKey)) {
      throw StateError(
        'Publisher identity changed; do not rotate keys implicitly.',
      );
    }
  } else {
    final random = Random.secure();
    defines = {
      'FLY_BOOK_CONTENT_KEY': base64UrlEncode(
        List.generate(32, (_) => random.nextInt(256)),
      ),
      'KNOWLEDGE_PUBLIC_KEY': base64UrlEncode(publicKey),
    };
    await definesFile.parent.create(recursive: true);
    await definesFile.writeAsString(jsonEncode(defines), flush: true);
  }
  final contentKey = _privateKey(defines['FLY_BOOK_CONTENT_KEY']);
  final codec = FlyBookCodec();
  final bytes = await codec.encode(
    book,
    contentKey: contentKey,
    signingSeed: seed,
  );
  final verified = await codec.decode(
    bytes,
    contentKey: contentKey,
    publicKey: publicKey,
  );
  if (verified.id != book.id || verified.chapters.length != chapters.length) {
    throw StateError('Book verification failed');
  }
  final output = File(args[1]);
  await output.parent.create(recursive: true);
  await output.writeAsBytes(bytes, flush: true);
  final digest = sha256.convert(bytes).toString().toUpperCase();
  await File('${output.path}.sha256.txt')
      .writeAsString('$digest  ${p.basename(output.path)}\n');
  stdout.writeln(
    'Created ${output.path}: ${chapters.length} chapters, ${assets.length} images, ${bytes.length} bytes.',
  );
  stdout.writeln(
    'Round-trip signature/decryption verification passed. Private keys were not printed.',
  );
}

List<int> _privateKey(Object? value) {
  try {
    if (value is! String) throw const FormatException();
    final key = base64Url.decode(base64Url.normalize(value.trim()));
    if (key.length != 32) throw const FormatException();
    return key;
  } on FormatException {
    throw StateError('Private book key is invalid. Its value is not logged.');
  }
}
