import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_providers.dart';
import 'notification_service.dart';
import '../../l10n/fly_localizations.dart';
import '../../l10n/settings_copy.dart';

class ReminderSettingsDialog extends ConsumerStatefulWidget {
  const ReminderSettingsDialog({this.embedded = false, super.key});
  final bool embedded;

  @override
  ConsumerState<ReminderSettingsDialog> createState() =>
      _ReminderSettingsDialogState();
}

class _ReminderSettingsDialogState
    extends ConsumerState<ReminderSettingsDialog> {
  ReminderSettings? _settings;
  String tr(String value) =>
      context.l10n.isZh ? value : settingsEnglish[value] ?? value;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final value = await ref.read(notificationServiceProvider).loadSettings();
    if (mounted) setState(() => _settings = value);
  }

  Future<void> _save(ReminderSettings value) async {
    setState(() => _settings = value);
    await ref.read(notificationServiceProvider).saveSettings(value);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final dialog = AlertDialog(
      title: Text(tr('提醒')),
      content: SizedBox(
        width: 430,
        child: settings == null
            ? const Center(child: CircularProgressIndicator.adaptive())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile.adaptive(
                    key: const ValueKey('reminder-master-toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Windows 原生提醒')),
                    subtitle: Text(tr('任务、客户跟进与订单交期')),
                    value: settings.enabled,
                    onChanged: (value) =>
                        _save(settings.copyWith(enabled: value)),
                  ),
                  const Divider(),
                  SwitchListTile.adaptive(
                    key: const ValueKey('review-reminder-toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      FlyLocalizations(Localizations.localeOf(context))
                          .t('dailyReview'),
                    ),
                    value: settings.reviewEnabled,
                    onChanged: settings.enabled
                        ? (value) =>
                              _save(settings.copyWith(reviewEnabled: value))
                        : null,
                  ),
                  if (settings.reviewEnabled)
                    TextButton(
                      onPressed: !settings.enabled
                          ? null
                          : () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: settings.reviewMinute ~/ 60,
                                  minute: settings.reviewMinute % 60,
                                ),
                              );
                              if (time != null && mounted) {
                                await _save(
                                  (_settings ?? settings).copyWith(
                                    reviewMinute: time.hour * 60 + time.minute,
                                  ),
                                );
                              }
                            },
                      child: Text(
                        TimeOfDay(
                          hour: settings.reviewMinute ~/ 60,
                          minute: settings.reviewMinute % 60,
                        ).format(context),
                      ),
                    ),
                  for (final item in const [
                    (0, '到期时'),
                    (10, '提前10分钟'),
                    (60, '提前1小时'),
                    (1440, '提前1天'),
                  ])
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr(item.$2)),
                      value: settings.offsetMinutes.contains(item.$1),
                      onChanged: settings.enabled
                          ? (selected) {
                              final values = {...settings.offsetMinutes};
                              if (selected ?? false) {
                                values.add(item.$1);
                              } else {
                                values.remove(item.$1);
                              }
                              _save(settings.copyWith(offsetMinutes: values));
                            }
                          : null,
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('完成')),
        ),
      ],
    );
    return widget.embedded ? dialog.content! : dialog;
  }
}
