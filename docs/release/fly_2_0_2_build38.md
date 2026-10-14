# Fly 2.0.2 build 38：Windows / Android 功能测试发布

发布日期：2026-10-14。版本：`2.0.2+38`。分支：`codex/fly-2-sync`。1.0 的 `master` 基线 `94efdc2d9ac34feb2f3d1b635302278b4671a414` 保持不变。

本版源码、官网及交接文档在当前 2.0 分支本地提交；没有推送远端或部署公网服务。当前发布提交以 `git log -1` 为准，精确提交 ID 另写在交付目录的 `manifest-Fly-2.0.2-build38.json`，避免文档内自引用提交号。构建产物与内部调试符号不提交 Git。

## 交付文件

| 文件 | 大小 |
| --- | --- |
| [Fly-Setup-2.0.2-build38-testing.exe](../../dist/Fly-Setup-2.0.2-build38-testing.exe) | 12.71 MiB |
| [Fly-2.0.2-build38-windows-test-20261014.zip](../../dist/Fly-2.0.2-build38-windows-test-20261014.zip) | 15.59 MiB |
| [Fly-2.0.2-build38-android-test-20261014.apk](../../dist/Fly-2.0.2-build38-android-test-20261014.apk) | 89.14 MiB |

[安装与测试说明](../../dist/README-Fly-2.0.2-build38-testing-20261014.md)。Windows 安装版直接运行安装程序；便携版完整解压，再运行 `fly.exe`，不能只复制 EXE。安装器最低系统设为 Windows 10，目标 x64，所需 Microsoft Visual C++ x64 运行库沿用既有安装提示。Windows 10 真机运行仍需用户验收。

Android 通用 APK：包名 `com.flyproduct.fly`，版本名 `2.0.2`，构建号 `38`，最低 SDK 24（Android 7.0），包含 ARM64、ARMv7、x86_64。签名验证通过，与 build 37 相同，可覆盖此前测试包。正式发行签名尚未配置。

## 本版内容

- 手机五个主入口、客户/订单列表与底部详情、任务完成反馈、层级清单路径和任务创建时间倒序。
- 文件相册/列表、多选数量、批量分享删除、视图/排列/标签记忆、图片优先、拍照导入、图片直接查看及非图片系统打开。
- 云与电脑手机连接方式、实体文件传输政策、永久删除墓碑、后台断连、前台恢复和三次失败停止。
- 同步详情中的待发送/待下载、等待源设备、实际进度、最近成功和错误；绿色连接不保证实体文件已全部可用。
- 周/月日历长按拖动改期、撤销和紧凑全天展开区，包含横竖屏调整。
- Android 读取权限声明与文件打开组件统一为 SDK 32 上限，修复正式 APK 清单合并冲突；旧系统写权限仍以 SDK 29 为上限，现有目录与权限交互保留。

## 官网与需求资料

文档、历史需求摘录、参考资料和官网均已清理相关品牌文字；历史品牌要求由最新品牌中性规则覆盖。专用支付演示和 SDK 已移除，官网保留产品展示、方案、订单及三设备授权基础。账户和付款适配器尚未接入：购买关闭，支付通知返回 410，不改变订单或发放授权，返回页仅提示。

19 份需求附件记录原始来源与当前整理副本的 SHA-256；部分副本不再是逐字原文。保留附件字节的 Git 属性使迁移后校验可复现。历史 Git 提交保留，不重写 1.0 历史。旧 Windows 营销资料改为通用平台说明，图片仍代表原阶段；整理后的素材包为 `dist/Fly-sales-material-v1.zip`。

已更新 [交接入口](../../FLY_PROJECT_HANDOFF.md)、[完整需求](../handoff/FLY_REQUIREMENTS.md)、[Mac 迁移](../handoff/MAC_TRANSFER.md)、[来源索引](../handoff/SOURCES.md)、[状态快照](../handoff/CURRENT_STATE.json)、四轮手机修复报告、官网说明和部署手册。

## 验证

- 静态分析无问题；完整 Flutter 回归 318 项通过，运行时连接隔离 FastAPI 服务，包含真实双客户端 HTTP 同步和 20 MiB LAN 实体传输。服务与临时数据已清理。
- 后端 18 项通过。官网全部 PHP 文件语法、核心授权测试及 HTTP 路由检查通过，验证匿名保护、购买关闭、通知无法确认付款、三设备限制和签名。
- Windows Release / Inno Setup 编译通过，EXE 版本为 `2.0.2+38`。便携 ZIP 完整性、依赖和 SQLite 原生库绑定检查通过，删除了遗留的测试专用绝对路径清单。
- Android Release 编译、APK 完整性、版本/最低系统/架构、签名及旧版签名一致性检查通过。构建中有插件 Kotlin 兼容提示，升级 Flutter SDK 时需复查相关插件；本次没有更换依赖。
- 文档与官网品牌文字/文件名扫描无匹配，19 份附件校验通过，暂存差异检查通过。

为功能测试设置 `ENABLE_LOCAL_LICENSE=false`，资料库维持 `ENABLE_KNOWLEDGE_HUB=false`；正式 Windows 构建脚本仍沿用原授权配置。本包不作为正式收费发行包。Windows 未做发行代码签名；Android 使用测试签名。

本次未更新公网后端。测试云同步、文件权限或永久删除时，应使用本次 `server/` 代码。扫码、相机、目录授权、系统打开、批量分享接收和前后台恢复需手机真机确认。macOS / iOS 未构建，真实业务数据不用于测试。

## 复现构建

原机 Flutter 3.47.7 / Dart 3.13.5。先恢复依赖和通过适当测试，再从工程根目录执行；SDK/Java 路径应按机器配置。两个平台依次构建，调试符号保存在忽略目录。

```sh
flutter build windows --release --no-pub --build-name=2.0.2 --build-number=38 --dart-define=FLY_APP_VERSION=2.0.2+38 --dart-define=ENABLE_LOCAL_LICENSE=false --dart-define=ENABLE_KNOWLEDGE_HUB=false --obfuscate --split-debug-info=private_symbols/2.0.2+38/windows
flutter build apk --release --no-pub --build-name=2.0.2 --build-number=38 --dart-define=FLY_APP_VERSION=2.0.2+38 --dart-define=ENABLE_LOCAL_LICENSE=false --dart-define=ENABLE_KNOWLEDGE_HUB=false --obfuscate --split-debug-info=private_symbols/2.0.2+38/android
```

Windows 安装器使用 `installer/Fly.iss`，`AppVersion=2.0.2`、`PackageName=Fly-Setup-2.0.2-build38-testing`；编译前核对 Release 目录版本与测试说明。便携包包含整个 Release 目录及文件依赖。

## SHA-256

- `Fly-Setup-2.0.2-build38-testing.exe`：`2A54597D495E9C204C61D5D54A24986AA21DDFD7ABACCFDD1AF84DE6EA193BF3`
- `Fly-2.0.2-build38-windows-test-20261014.zip`：`FCFDD34DED4CA36D73882A64B51CCCCBA2C9E1B6D21AAFEB217C792A28BE6637`
- `Fly-2.0.2-build38-android-test-20261014.apk`：`90986189995B37D41B0822CD9FA3868D07F677DF12CAB834AFE35A875F88D0C1`

对应 `.sha256.txt` 位于各产物旁；后续重打包后应重新计算，不能沿用本次值。
