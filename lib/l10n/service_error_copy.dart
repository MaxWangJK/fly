import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'fly_localizations.dart';

// Translate only known application messages. Preserve unknown platform diagnostics
// and parameter values (especially file paths); never translate persisted content.
const _messages = <String, String>{
  "本节已有货物，请从剩余区域选择位置添加": "This section already contains cargo. Add cargo through a remaining area.",
  "Fly 数据目录尚未初始化": "Fly data directory is not initialized.",
  "数据目录尚未初始化": "Data directory is not initialized.",
  "备份期间库文件发生变化，请重试": "Library files changed during backup. Please retry.",
  "备份缺少库文件清单": "The backup is missing its library manifest.",
  "库文件清单格式无效": "Invalid library manifest format.",
  "无效库文件条目": "Invalid library file entry.",
  "库文件路径或摘要无效": "Invalid library file path or checksum.",
  "缺少备份文件对象，请同时复制 .fly-file-objects 文件夹": "Backup file objects are missing. Copy the .fly-file-objects directory as well.",
  "备份文件摘要校验失败": "Backup file checksum verification failed.",
  "请选择有效的 Fly ZIP 备份包。": "Select a valid Fly ZIP backup.",
  "备份缺少 metadata.json 或 fly.db。":
      "The backup is missing metadata.json or fly.db.",
  "备份元数据格式无效。": "Invalid backup metadata format.",
  "当前 Fly 不支持该备份包版本。": "This backup version is not supported by Fly.",
  "备份数据库完整性检查失败。": "Backup database integrity check failed.",
  "恢复后的数据目录缺少 fly.db。": "The restored data directory is missing fly.db.",
  "原文件不存在": "The original file does not exist.",
  "请先移除待删除分节中的货物条目，避免丢失柜内或暂存区货物。": "Remove cargo entries from the affected sections first to avoid losing loaded or staged cargo.",
  "此分节有关联的手动搬运货物，请先移回原分节再重新计算，避免覆盖人工摆放。": "This section has manually moved cargo. Move it back to the original section before recalculating to preserve manual placement.",
  "名称不能为空，且不能包含路径或特殊字符":
      "Enter a name without path separators or special characters.",
  "目标文件夹不存在或已删除": "The destination folder does not exist or has been deleted.",
  "同级文件夹名称已存在": "A sibling folder already has this name.",
  "文件夹不存在": "Folder not found.",
  "不能移动到自身或子文件夹": "Cannot move a folder into itself or a descendant.",
  "目标位置已有同名文件夹": "The destination already contains a folder with this name.",
  "文件夹无法恢复": "The folder cannot be restored.",
  "恢复位置存在同名文件夹，请先重命名现有文件夹":
      "Rename the existing folder at the restore location before restoring.",
  "当前平台请使用复制文件路径": "Use Copy file path on this platform.",
  "当前平台暂不支持原生拖出": "Native drag-out is not supported on this platform.",
  "文件路径不在 FlyData 中": "The file path is outside FlyData.",
  "无效文件夹 ID": "Invalid folder ID.",
  "仅支持普通文件": "Only regular files are supported.",
  "复制期间源文件大小发生变化，请重试":
      "The source file changed size during copying. Please retry.",
  "无法确认临时文件归属": "Cannot establish ownership of the temporary file.",
  "目标文件夹不存在": "Destination folder not found.",
  "笔记不存在或已删除": "The note does not exist or has been deleted.",
  "文件不存在": "File not found.",
  "业务附件不能剪切离开所属记录，请复制到我的文件": "Business attachments cannot be cut away from their records. Copy them to My files.",
  "业务附件请从所属客户或订单中删除":
      "Delete business attachments from their owning customer or order.",
  "文件无法恢复": "The file cannot be restored.",
  "标签长度需要 1–100 字": "Tags must contain 1–100 characters.",
  "客户不存在": "Customer not found.",
  "工厂和产品不能为空": "Factory and product are required.",
  "客户级别不存在或已停用": "The customer category does not exist or is inactive.",
  "编辑会话已关闭": "The editing session is closed.",
  "表格需要 1–200 行": "Tables must have 1–200 rows.",
  "表格单元格必须是等宽字符串数组":
      "Table rows must contain strings and have equal column counts.",
  "附件不能为空": "An attachment is required.",
  "块文字必须为字符串": "Block text must be a string.",
  "Checklist 状态必须为布尔值": "Checklist state must be a boolean.",
  "笔记文件夹不存在": "Note folder not found.",
  "请输入 1–500 字笔记标题": "Enter a note title with 1–500 characters.",
  "笔记标题不能为空或超过 500 字": "Note titles must contain 1–500 characters.",
  "重复块 ID": "Duplicate block ID.",
  "笔记不存在": "Note not found.",
};
const _prefixes = <String, String>{
  '文件备份对象校验失败：': 'Backup object verification failed: ',
  '文件不存在：': 'File not found: ',
  '找不到 Sheet：': 'Sheet not found: ',
};

String localizedServiceError(Object? error, {required bool isZh}) {
  if (isZh) return error.toString();
  String message;
  if (error is StateError) {
    message = error.message;
  } else if (error is ArgumentError) {
    message = error.message?.toString() ?? error.toString();
  } else if (error is FormatException) {
    message = error.message;
  } else if (error is PlatformException) {
    message = error.message ?? error.code;
  } else {
    message = error.toString();
  }
  // Some recoverable sessions persist the textual error rather than the object.
  for (final prefix in [
    'Bad state: ',
    'Invalid argument(s): ',
    'FormatException: ',
  ]) {
    if (message.startsWith(prefix)) {
      message = message.substring(prefix.length);
      break;
    }
  }
  final exact = _messages[message];
  if (exact != null) return exact;
  for (final entry in _prefixes.entries) {
    if (message.startsWith(entry.key)) {
      return entry.value + message.substring(entry.key.length);
    }
  }
  return error.toString();
}

extension ServiceErrorContext on BuildContext {
  String flyError(Object? error) =>
      localizedServiceError(error, isZh: FlyLocalizations.of(this).isZh);
}
