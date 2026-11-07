import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly/features/files/data/managed_file_repository.dart';
import 'package:fly/features/files/data/managed_file_storage.dart';
import 'package:fly/features/files/data/media_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fly-test/media');
  late Directory root;
  late File source;
  final outputs = <String>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fly-media-tests-');
    source = await File('${root.path}/product.heic').writeAsBytes([1, 2, 3, 4]);
    outputs.clear();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    for (final path in outputs) {
      expect(await Directory(path).exists(), isFalse);
    }
    await root.delete(recursive: true);
  });
  void native(Future<Object?> Function(MethodCall) handler) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);

  test('other platforms leave source bytes and names unchanged', () async {
    final input = XFile(source.path);
    final batch = await MediaImportService(ios: false).prepare(input);
    expect(identical(batch.files.single, input), isTrue);
    await batch.dispose();
    expect(await source.readAsBytes(), [1, 2, 3, 4]);
  });

  test('compatible original is not re-encoded or removed', () async {
    native((call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      outputs.add(args['output'] as String);
      return {'path': source.path, 'name': 'product.jpg'};
    });
    final batch = await MediaImportService(
      ios: true,
      channel: channel,
    ).prepare(XFile(source.path));
    expect(batch.files.single.name, 'product.jpg');
    await batch.dispose();
    await batch.dispose();
    expect(await source.readAsBytes(), [1, 2, 3, 4]);
  });

  test(
    'hash, length and extension describe converted bytes; source is preserved',
    () async {
      final bytes = [255, 216, 255, 219, 9, 8, 7];
      native((call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final dir = args['output'] as String;
        outputs.add(dir);
        final file = await File('$dir/product.jpg').writeAsBytes(bytes);
        return {'path': file.path, 'name': 'product.jpg'};
      });
      final batch = await MediaImportService(
        ios: true,
        channel: channel,
      ).prepare(XFile(source.path));
      final storage = ManagedFileStorage('${root.path}/data');
      final imported = await storage.import(
        batch.files.single.path,
        pickedFile: batch.files.single,
      );
      await batch.dispose();
      expect(imported.name, 'product.jpg');
      expect(imported.sha256, sha256.convert(bytes).toString());
      expect(imported.size, bytes.length);
      expect(ManagedFileRepository.mime(imported.name), 'image/jpeg');
      expect(
        await File(storage.absolute(imported.relativePath)).readAsBytes(),
        bytes,
      );
      expect(await source.readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test(
    'conversion failure cleans partial output and retains original',
    () async {
      native((call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        outputs.add(args['output'] as String);
        await File('${args['output']}/partial.mp4').writeAsBytes([9]);
        throw PlatformException(code: 'CONVERSION', message: '无法转换视频');
      });
      await expectLater(
        MediaImportService(
          ios: true,
          channel: channel,
        ).prepare(XFile(source.path)),
        throwsStateError,
      );
      expect(await source.exists(), isTrue);
    },
  );

  test(
    'cancellation reaches native export and cleans only scoped output',
    () async {
      final started = Completer<void>();
      final exported = Completer<Object?>();
      String? request;
      native((call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        if (call.method == 'normalize') {
          outputs.add(args['output'] as String);
          request = args['id'] as String;
          started.complete();
          return exported.future;
        }
        if (call.method == 'cancel') {
          expect(args['id'], request);
          exported.completeError(PlatformException(code: 'CANCELLED'));
        }
        return 0.0;
      });
      final cancellation = ImportCancellation();
      final result = MediaImportService(
        ios: true,
        channel: channel,
      ).prepare(XFile(source.path), cancellation: cancellation);
      final assertion = expectLater(result, throwsA(isA<ImportCancelled>()));
      await started.future;
      cancellation.cancel();
      await assertion;
      expect(await source.exists(), isTrue);
    },
  );

  test('invalid or empty output cannot be imported and never deletes foreign files', () async {
    native((call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      outputs.add(args['output'] as String);
      return {'path': '${root.path}/foreign.jpg', 'name': 'wrong.jpg'};
    });
    final foreign = await File('${root.path}/foreign.jpg').writeAsBytes([8]);
    await expectLater(
      MediaImportService(
        ios: true,
        channel: channel,
      ).prepare(XFile(source.path)),
      throwsStateError,
    );
    expect(await foreign.readAsBytes(), [8]);
  });

  test(
    'Live pick keeps still and motion, and releases native staging once',
    () async {
      var releases = 0;
      native((call) async {
        if (call.method == 'pick') {
          return {
            'token': 'picked',
            'files': [source.path, '${root.path}/product (Live).mov'],
          };
        }
        expect(call.method, 'releasePick');
        expect((call.arguments as Map)['token'], 'picked');
        releases++;
        return null;
      });
      final batch = await MediaImportService(
        ios: true,
        channel: channel,
      ).pick();
      expect(batch.files.length, 2);
      expect(batch.files.last.name, 'product (Live).mov');
      await batch.dispose();
      await batch.dispose();
      expect(releases, 1);
      expect(await source.exists(), isTrue);
    },
  );

  test('cancelled jobs do not start native work', () async {
    final cancellation = ImportCancellation()..cancel();
    await expectLater(
      MediaImportService(
        ios: true,
        channel: channel,
      ).prepare(XFile(source.path), cancellation: cancellation),
      throwsA(isA<ImportCancelled>()),
    );
  });
}
