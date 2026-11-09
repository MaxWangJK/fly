import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/fly_localizations.dart';
import 'update_controller.dart';

class AppUpdateNotice extends ConsumerWidget {
  const AppUpdateNotice({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(updateControllerProvider);
    final release = controller.result?.latest;
    if (!controller.showNotice || release == null) return child;
    final zh = context.l10n.isZh;
    return Stack(
      children: [
        child,
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              margin: const EdgeInsets.all(12),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        zh
                            ? '发现新版本 ${release.version.display}'
                            : 'Update available: ${release.version.display}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        zh ? '下载后由系统完成安装。' : 'Download the update, then install it with your system.',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: controller.dismiss,
                            child: Text(zh ? '稍后' : 'Later'),
                          ),
                          FilledButton(
                            onPressed: controller.openingDownload
                                ? null
                                : controller.download,
                            child: Text(zh ? '下载更新' : 'Download update'),
                          ),
                        ],
                      ),
                      if (controller.downloadFailed)
                        Text(
                          zh
                              ? '无法打开下载链接，请重试。'
                              : 'Could not open the download. Please retry.',
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class UpdateSettingsPanel extends ConsumerWidget {
  const UpdateSettingsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(updateControllerProvider);
    final zh = context.l10n.isZh;
    final result = controller.result;
    final message = controller.checkFailed
        ? (zh
              ? '暂时无法检查更新，请稍后重试。'
              : 'Update check failed. Please try again later.')
        : result == null
        ? ''
        : !result.supported
        ? (zh
              ? '此平台暂未提供安装包更新检测。'
              : 'Package updates are not available for this platform yet.')
        : result.latest == null
        ? (zh ? '服务器尚未发布可用安装包。' : 'No release package has been published yet.')
        : result.isNewer
        ? (zh
              ? '可更新至 ${result.latest!.version.display}'
              : 'Update to ${result.latest!.version.display}')
        : (zh ? '当前已是最新版本。' : 'You are up to date.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('check-app-updates'),
              onPressed: controller.checking ? null : () => controller.check(),
              icon: controller.checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_alt, size: 18),
              label: Text(zh ? '检查更新' : 'Check for updates'),
            ),
            if (result?.isNewer == true)
              FilledButton(
                onPressed: controller.openingDownload
                    ? null
                    : controller.download,
                child: Text(zh ? '下载更新' : 'Download update'),
              ),
          ],
        ),
        if (message.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(message)),
        if (controller.downloadFailed)
          Text(
            zh ? '无法打开下载链接，请重试。' : 'Could not open the download. Please retry.',
          ),
      ],
    );
  }
}
