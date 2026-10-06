# Fly 1.0.0+29 最终功能构建记录（2026-10-06）

## Dashboard 改动

- 保留顶部五张业务数字卡，以及底部今日需跟进客户、紧急订单列表。
- 移除重复展示相同计数的“当前工作分布”柱状图，以单一低噪声的“我的聚焦”面板替换：人生主线、本周重点、今日提醒。
- 三段内容可直接点击编辑；Enter / Ctrl+Enter 保存、Esc 取消、点击外部保存。悬停时显示轻量编辑入口。首次使用只显示提示语，不向数据库写入预设目标。
- 历史从 Dashboard 右侧面板打开，不离开当前页面。

## 数据与迁移

- 数据库模式升级到 16：`dashboard_focuses` 存放人生主线和本周重点，`dashboard_daily_focuses` 按本地日期存放今日提醒，`dashboard_focus_histories` 保存真正改写前的非空旧值。
- 保存采用事务；内容相同（忽略首尾空白）不产生新版本。今日提醒不会跨天覆盖，本周重点不会每周自动清空。
- 14→16 与 15→16 迁移测试验证已有业务数据保留；不新增第三方依赖。

## 界面与语言

- 面板颜色取自 FlyColorScheme，覆盖现有全部配色的浅色和深色模式；已检查薄荷云境下的真实 Dashboard 渲染。
- 固定界面文字提供中英文；用户填写的目标保持原文。
- 窄窗口保留可编辑布局，较长内容最多预览三行，进入编辑可读取完整文本。

## 发布验证

- `dart format`：已格式化本轮 Dart 文件。
- `flutter analyze --no-pub`：通过，0 个问题。
- `flutter test --no-pub --concurrency=1`：通过，228 项测试。
- `flutter build windows --release`：通过，Windows x64 Release 构建成功。
- `flutter run -d windows --release`：通过独立入口使用隔离的 FlyData 启动；自动截图确认 Dashboard 展示五张业务卡、“我的聚焦”已保存内容与底部业务列表。该检查未使用现有用户数据目录。
- Windows 安装器：[Fly-Setup-1.0.0-build29.exe](../../dist/Fly-Setup-1.0.0-build29.exe)，大小 12,545,268 字节；SHA256：`603F78CA43AB74A0DF850E5B2F3817F83893EA29F368A07617A139AA3ABBDB51`，与校验文件一致。

## 发布前说明

本包是 **1.0 功能最终候选包**，但尚不能视为已完成商业发布验收：未配置代码签名，Windows 仍可能显示“未知发布者”；尚需在干净 Windows 环境人工验证安装、旧版升级、激活、卸载保留 FlyData 与真实旧库备份恢复。发布者仍须确认收费授权、隐私与第三方许可，以及 Inno Setup 7 的商用许可；本次编译器明确输出 `Non-commercial use only`。详见 [1.0 发布计划](fly_1_0_release_plan.md)。
