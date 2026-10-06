import 'package:flutter/material.dart';

import 'fly_localizations.dart';

/// Fixed Focus Board UI copy only. User-written goals are never translated.
const dashboardFocusEnglish = <String, String>{
  '我的聚焦': 'My Focus',
  '人生主线': 'Main Mission',
  '本周重点': 'Weekly Focus',
  '今日提醒': "Today's Focus",
  '历史': 'History',
  '聚焦历史': 'Focus history',
  '编辑': 'Edit',
  '关闭历史': 'Close history',
  '暂无历史': 'No history yet',
  '点击这里写下你当前最重要的长期目标': 'Write your most important long-term goal',
  '这周最重要的一件事是什么？': 'What matters most this week?',
  '今天必须完成什么？': 'What must be done today?',
  '点击即可编辑': 'Click to edit',
  '保存中…': 'Saving…',
  '保存失败，请重试': 'Could not save. Please try again.',
  '聚焦内容读取失败': 'Unable to load focus',
  '重试': 'Retry',
  '旧版本': 'Previous version',
};

extension DashboardFocusCopyContext on BuildContext {
  String focusCopy(String value) =>
      l10n.isZh ? value : dashboardFocusEnglish[value] ?? value;
}
