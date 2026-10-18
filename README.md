# Fly

2.0 接续开发或迁移，请先读 [项目交接入口](FLY_PROJECT_HANDOFF.md) 和 [完整需求](docs/handoff/FLY_REQUIREMENTS.md)。当前源码 2.0.6+42：客户文件可新增文件和子目录、目录网格自适应、手机移除账户设置、复盘填写后收起为卡片，保留此前安卓全屏和电脑扫码功能。功能已保存于 `codex/fly-2-sync` 的 `311c7b3` 检查点；Windows / Android 当前包均为 build 42。[本轮记录](docs/release/fly_2_0_6_build42.md)、[APK 台账](docs/handoff/APK_RELEASES.md)。下面保留原 1.0 说明。

Fly 是面向外贸个人工作的 Windows x64、本地优先桌面工作区，基于 Flutter、Riverpod、Drift 和 SQLite。当前 1.0 范围涵盖 Dashboard、客户、订单、任务、日历、四象限、今日复盘、文件、笔记、3D 装柜、全局搜索和备份。完整边界见 [产品范围](docs/product/v1_scope.md)，发布状态见 [1.0 发布计划](docs/release/fly_1_0_release_plan.md)。

## 开发

以 `pubspec.yaml` 为应用版本唯一来源。当前 Windows 开发环境的 Flutter 位于 `D:\ProgramData\flutter`；其他机器可使用 PATH 中的 Flutter。

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run -d windows
```

正式打包入口：

```powershell
./scripts/build_installer.ps1
```

脚本依次完成依赖恢复、静态检查、测试、启用离线授权的 Windows Release 构建和 Inno Setup 安装包。若任一门槛失败，不应发布旧 `dist` 文件。私有授权密钥与调试符号不得随安装包分发；公钥在 `license_tools/public_key.txt`。签名证书、商业授权政策与安装器许可由发布者自行确认。

## 数据安全

2026-10-16 安卓正式签名备案材料及后续发布：[签名与备案说明](docs/release/android_release_signing_20261016.md)。原测试签名 APK 继续保留；正式签名换装前先完整备份。

首次启动请选择专用 FlyData 目录。安装或卸载 Fly 不会清空这个目录。自动备份失败时应用仍可打开，但会显示提醒；发布前应实际执行备份与恢复演练。大量文件使用增量对象仓库，移动备份时必须连同 ZIP 旁的 `.fly-file-objects` 一起复制。

只有 Windows x64 是 1.0 目标平台。生成了其他平台工程文件并不代表已通过这些平台的构建或测试。
