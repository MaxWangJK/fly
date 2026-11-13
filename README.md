# Fly

2026-11-13最新：Windows/Android2.0.27+63已交付。手机仅选择客户状态，隐藏新增/编辑/删除；桌面改为右上角小圆红叉、限定悬停范围并恢复标签间距。18项相关用例和静态检查、8项提交后重复复验、两端构建及原签名/包核验通过。[交付](docs/release/fly_2_0_27_build63.md) / [接续入口](FLY_PROJECT_HANDOFF.md)。

2026-11-13上一交付：Windows/Android2.0.26+62已打包，包含导入自动创建级别/状态、新建客户状态新增/改名/停用及历史名称保留；48项相关用例和静态检查、提交后12项重复复验及两端构建/包核验通过。电脑和手机均需更新。[交付](docs/release/fly_2_0_26_build62.md) / [接续入口](FLY_PROJECT_HANDOFF.md)。

2026-11-13上一交付：Windows/Android2.0.25+61已打包，包含实体文件改名、局域网实体名称更新和客户创建弹框修复；50项相关用例与静态检查、12项提交后复验、两端构建及包核验通过。[交付](docs/release/fly_2_0_25_build61.md) / [接续入口](FLY_PROJECT_HANDOFF.md)。

2026-11-12上一交付：Windows/Android2.0.24+60已打包，减少视频反复同步校验、播放界面重建和退出/错误时的后台工作。43项相关用例、静态检查、原生Windows与AOT合成验证、两端构建和包核验通过。[修复与边界](docs/release/video_performance_20261112.md) / [交付](docs/release/fly_2_0_24_build60.md) / [接续入口](FLY_PROJECT_HANDOFF.md)。以下保留历史记录。

2026-11-09当前：源码/Windows **2.0.21+57**、SQLite20、后台迁移0005。新增[极简匿名安装/日活统计](docs/analytics.md)、[客户创建框Excel导入及模板](docs/customer_import.md)、[Windows/Android更新检测](docs/app_updates.md)，没有其他统计事件或业务关联。客户端全量539通过/3跳过、后台86通过，应用静态检查与Windows构建/包核验通过。[交付与安装包](docs/release/anonymous_import_updates_20261109.md) / [Ubuntu原生升级命令](server/deploy/analytics-updates.md)。Android现有build50不含本轮新增，Apple平台及真实服务器未验证。接续开发以[项目交接](FLY_PROJECT_HANDOFF.md)为准，以下保留历史交付记录。

2026-11-01 本轮交付：[2.0.7 build43 记录](docs/release/fly_2_0_7_build43.md)、[云同步调度与 API](docs/architecture/cloud_sync_runtime_20261101.md)、[已有 PHP 官网的详细 Ubuntu 部署](server/deploy/cloud_sync_20261101.md)。采用启动/修改立即同步、WebSocket 提醒和每五分钟补查；系统后台推送留作下一阶段。实际交付结果与校验值见本轮报告和包台账。

云同步新增 [邮箱注册与密码登录](docs/release/email_cloud_auth_20261101.md)：后台图形校验、六位邮箱码、确认密码；原临时空间可绑定邮箱继续使用。云端仍不传图片和文件内容，已纳入 build43；线上部署由所有者执行。

新增 [基础/航向双复盘方案](docs/product/review_compass_20261101.md)：保留原有复盘与卡片，航向方案当前可浏览并免费体验，支持小实验转任务和七日校准；未接入支付，已纳入 build43。

2026-11-01历史源码为 **2.0.7+43 / SQLite schema 20**：默认本地同步，可选云端数据同步，支持工作电脑、手机、家庭电脑自动合并、一次性设备接入码和本地下载续传。源码 `55bd11d` 已保存并完成 build43 Windows/Android 打包；本轮未执行远端推送或真实部署。见 [本轮开发记录](docs/release/sync_multi_device_20261101.md) 与 [已有官网的 Ubuntu 接入](server/deploy/cloud_sync_20261101.md)。

2.0 接续开发或迁移，请先读 [项目交接入口](FLY_PROJECT_HANDOFF.md) 和 [完整需求](docs/handoff/FLY_REQUIREMENTS.md)。上一已打包版本为 2.0.6+42：客户文件可新增文件和子目录、目录网格自适应、手机移除账户设置、复盘填写后收起为卡片，保留此前安卓全屏和电脑扫码功能。这些历史功能已保存于 `codex/fly-2-sync` 的 `311c7b3` 检查点；上述历史包为 build42，当时使用 build43，当前以顶部交付为准。[历史打包记录](docs/release/fly_2_0_6_build42.md)、[APK 台账](docs/handoff/APK_RELEASES.md)。下面保留原 1.0 说明。

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

2026-10-18 源码续补：手机长按和电脑右键普通图片/文件新增“移动”，支持多级目录及根目录；尚未重新打包，见 [功能说明](docs/release/file_move_20261018.md)。

同日续补支持多选批量移动，包含原地跳过、失败项保留和结果详情；源码已更新，旧安装包未包含此功能。

2026-10-31：客户/订单列表新增字段名称，手机卡片显示值标签；源码及此前文件移动已保存于 `96261db`，现有安装包未更新。GitHub 仓库：[MaxWangJK/fly](https://github.com/MaxWangJK/fly)，实际上传状态见 [上传记录](docs/release/github_upload_20261031.md)。
