import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/fly_book.dart';
import '../presentation/fly_book_document.dart';

/// Encrypted, authenticated offline distribution, not unbreakable DRM.
/// Only the signed ciphertext is persisted by the reader.
class FlyBookCodec {
  static const maxFileBytes = 64 * 1024 * 1024;
  static const maxPlainBytes = 64 * 1024 * 1024;
  static final _magic = ascii.encode('FLYBOOK1');
  static const _headerSize = 28;

  Future<Uint8List> encode(
    FlyBook book, {
    required List<int> contentKey,
    required List<int> signingSeed,
  }) async {
    _key(contentKey);
    if (signingSeed.length != 32) {
      throw const FormatException('Invalid publisher key');
    }
    final checked = FlyBook.fromJson(book.toJson());
    FlyBookDocument.validate(checked);
    final plain = utf8.encode(jsonEncode(checked.toJson()));
    if (plain.length > maxPlainBytes) {
      throw const FormatException('Book is too large');
    }
    final compressed = gzip.encode(plain);
    if (compressed.length + _headerSize + 80 > maxFileBytes) {
      throw const FormatException('Book is too large');
    }
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final header = Uint8List(_headerSize)..setRange(0, 8, _magic);
    final view = ByteData.sublistView(header);
    view.setUint32(8, plain.length, Endian.big);
    view.setUint32(12, compressed.length, Endian.big);
    header.setRange(16, 28, nonce);
    final box = await algorithm.encrypt(
      compressed,
      secretKey: SecretKey(contentKey),
      nonce: nonce,
      aad: header,
    );
    final signed = Uint8List.fromList([
      ...header,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    final pair = await Ed25519().newKeyPairFromSeed(signingSeed);
    final signature = await Ed25519().sign(signed, keyPair: pair);
    return Uint8List.fromList([...signed, ...signature.bytes]);
  }

  Future<FlyBook> decode(
    List<int> file, {
    required List<int> contentKey,
    required List<int> publicKey,
  }) async {
    _key(contentKey);
    if (publicKey.length != 32 ||
        file.length < _headerSize + 80 ||
        file.length > maxFileBytes) {
      throw const FormatException('Invalid .fly book size or verification key');
    }
    final bytes = Uint8List.fromList(file);
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException('Not a supported .fly book');
      }
    }
    final header = Uint8List.sublistView(bytes, 0, _headerSize);
    final fields = ByteData.sublistView(header);
    final expanded = fields.getUint32(8, Endian.big);
    final compressed = fields.getUint32(12, Endian.big);
    if (expanded < 2 ||
        expanded > maxPlainBytes ||
        compressed < 1 ||
        bytes.length != _headerSize + compressed + 80) {
      throw const FormatException('Invalid .fly book header');
    }
    final signed = Uint8List.sublistView(bytes, 0, bytes.length - 64);
    if (!await Ed25519().verify(
      signed,
      signature: Signature(
        Uint8List.sublistView(bytes, bytes.length - 64),
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    )) {
      throw const FormatException('Book signature verification failed');
    }
    final decrypted = await AesGcm.with256bits().decrypt(
      SecretBox(
        Uint8List.sublistView(bytes, _headerSize, _headerSize + compressed),
        nonce: Uint8List.sublistView(header, 16),
        mac: Mac(
          Uint8List.sublistView(bytes, _headerSize + compressed, signed.length),
        ),
      ),
      secretKey: SecretKey(contentKey),
      aad: header,
    );
    final sink = _BoundedBookSink(expanded);
    final decoder = gzip.decoder.startChunkedConversion(sink);
    decoder.add(decrypted);
    decoder.close();
    final plain = sink.bytes.takeBytes();
    if (plain.length != expanded) {
      throw const FormatException('Invalid book payload size');
    }
    final data = jsonDecode(utf8.decode(plain));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid book payload');
    }
    final book = FlyBook.fromJson(data);
    FlyBookDocument.validate(book);
    return book;
  }

  static void _key(List<int> key) {
    if (key.length != 32) throw const FormatException('此构建未配置书籍阅读密钥，请更新阅读器。');
  }
}

class _BoundedBookSink extends ByteConversionSink {
  _BoundedBookSink(this.limit);
  final int limit;
  final bytes = BytesBuilder();
  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > limit) {
      throw const FormatException('Expanded book size limit exceeded');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
