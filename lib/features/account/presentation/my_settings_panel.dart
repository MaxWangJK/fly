import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../l10n/fly_localizations.dart';
import '../../tasks/presentation/task_providers.dart';
import '../data/local_profile.dart';

Future<void> showMySettings(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Builder(
                builder: (context) => IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            const MySettingsPanel(),
          ],
        ),
      ),
    ),
  ),
);

class MySettingsPanel extends ConsumerStatefulWidget {
  const MySettingsPanel({super.key});
  @override
  ConsumerState<MySettingsPanel> createState() => _MySettingsPanelState();
}

class _MySettingsPanelState extends ConsumerState<MySettingsPanel> {
  final name = TextEditingController();
  Uint8List? avatar;
  bool loaded = false, busy = false;
  String? error;
  String t(String zh, String en) => context.l10n.isZh ? zh : en;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickAvatar() => run(() async {
    final XFile? file = Platform.isAndroid || Platform.isIOS
        ? await ImagePicker().pickImage(
            source: ImageSource.gallery,
            maxWidth: 512,
            maxHeight: 512,
            imageQuality: 85,
          )
        : await openFile(
            acceptedTypeGroups: [
              const XTypeGroup(
                label: 'Images',
                extensions: ['png', 'jpg', 'jpeg', 'webp'],
              ),
            ],
          );
    if (file == null) return;
    if (await file.length() > 8 * 1024 * 1024) {
      throw StateError(t('请选择小于 8 MB 的图片', 'Choose an image under 8 MB'));
    }
    final codec = await ui.instantiateImageCodecWithSize(
      await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()),
      getTargetSize: (width, height) => width >= height
          ? ui.TargetImageSize(width: width.clamp(1, 256))
          : ui.TargetImageSize(height: height.clamp(1, 256)),
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final bytes = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (mounted && bytes != null) {
          setState(() => avatar = bytes.buffer.asUint8List());
        }
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  });

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(localProfileProvider);
    if (!loaded && profile.hasValue) {
      loaded = true;
      name.text = profile.value!.name;
      avatar = profile.value!.avatar;
    }
    return Column(
      key: const ValueKey('my-settings-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t('个人资料', 'Profile'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: avatar == null ? null : MemoryImage(avatar!),
                child: avatar == null
                    ? const Icon(Icons.person_outline, size: 36)
                    : null,
              ),
              TextButton(
                key: const ValueKey('my-pick-avatar'),
                onPressed: busy ? null : pickAvatar,
                child: Text(t('设置头像', 'Choose avatar')),
              ),
            ],
          ),
        ),
        TextField(
          key: const ValueKey('my-display-name'),
          controller: name,
          enabled: loaded,
          maxLength: 80,
          decoration: InputDecoration(labelText: t('我的名字', 'My name')),
        ),
        FilledButton.tonal(
          key: const ValueKey('my-save-profile'),
          onPressed: busy || !loaded
              ? null
              : () => run(() async {
                  await LocalProfileRepository(ref.read(databaseProvider))
                      .save(name.text, avatar);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(t('个人资料已保存', 'Profile saved'))),
                    );
                  }
                }),
          child: Text(t('保存个人资料', 'Save profile')),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
