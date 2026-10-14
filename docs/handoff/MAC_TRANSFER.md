# Fly 从 Windows 转移到 Mac

本文件提供迁移说明。2026-10-14 已将最新 2.0 功能与文档本地提交并生成 Windows / Android 测试包；没有执行实际文件迁移、Mac 安装或分支切换。

## 1. Git 是否需要切换

不需要。已核实 `.git` 是项目内真实目录，不是指向外部 worktree 的文件；当前分支为 `codex/fly-2-sync`，本版 HEAD 可由 `git log -1` 核实，master 保持 1.0 基线。

只要完整压缩/复制当前工程，包含隐藏 `.git` 和全部未提交修改/新增文件，解压后会保持这份工作区和分支。Git 的 HEAD/分支等存于仓库元数据内；参见 [Git 官方仓库布局](https://git-scm.com/docs/gitrepository-layout)。

只拷贝 Release/安装包或漏掉 `.git` 不足以迁移开发工程。本版已本地提交，远端尚未推送；从远端 clone/pull 可能缺最新提交。Git 导出源码不包含历史、内部签发密钥、真实 FlyData 或发行包，这些应按用途另行安全转移。

解压后只读确认即可：

```sh
cd /你的路径/fly
git branch --show-current
git status --short
git log -3 --oneline
```

分支应为 `codex/fly-2-sync`。本次提交完成后工作区应为干净状态；以后若有新增改动，应一并带走。不要用重置、restore、clean 或切 master 准备迁移。

## 2. 哪些内容需要带走

### 开发工程

必须保留 `.git`、`lib`、`test`、`assets`、各平台工程、`pubspec.yaml`/lock、源码中的生成绑定、`server`、`web`、`scripts`、`tool`、`docs` 和根目录交接入口。官网、营销资料和交接文档已纳入本次提交。内部私钥和构建包仍属于忽略文件，迁移时另行核对。

整目录打包可以，但通常会混入很大的 Windows 生成物和机器环境。`build`、`.dart_tool`、`server/.venv`、平台 ephemeral/Gradle 缓存、旧日志/产物等不是 Mac 可直接复用的运行环境；它们可随归档保留作为证据，新机仍须重新生成依赖/构建。

`dist` 和 `artifacts` 有旧包、截图或报告，不能把它们当作最新源代码。当前交接已另存少量可迁移截图和验证状态。

### 真实业务数据

**复制 `E:\workSpace\fly` 不自动等于复制用户客户/订单/文件。** App 的 FlyData 是用户另外选择的目录；根目录选择记录在系统应用支持目录的 `settings.json`，未必在源码树。

若还要带真实业务数据，应先从应用的数据设置确认实际目录，使用完整备份或在保存并关闭软件后复制完整 FlyData：`fly.db`、`attachments/`、`files/`、客户/订单相关内容和其他必要资源。不要在数据库正写入时只复制单个 db 文件。

大文件增量备份必须将 ZIP/manifest 和同目录 `.fly-file-objects` 一起带走；只有 ZIP 不算完整。Mac 首次运行应在隔离副本恢复/选择新路径，不能沿用不存在的 Windows `E:` 路径。新版本 schema 19 不应让旧 1.0 客户端直接覆盖保存。

### 密钥、登录与工具

- 内部授权私钥、知识包签名种子如位于 Git 忽略的 private 目录，整目录归档也可能包含它们。只给本人可信开发机保存，不向客户或普通资料分享；保持原密钥，不重新初始化覆盖。
- 本交接文档和原始需求副本未包含私钥内容；不要为了让 ChatGPT 理解产品把生产 `.env` 或私钥贴到对话里。
- Windows 系统安全存储、DPAPI 离线试用、机器码、账号凭据和通知注册不是通过复制源码自动转成 Mac Keychain；新机按平台重新登录/配置，业务备份不作为授权身份克隆。
- Git 的全局作者/认证配置和 Codex 的全局 skills 在源码目录之外，不会自然随工程迁移。四个自定义 Flutter skills 的参考副本已经包含，但未在 Mac 安装。
- 项目目录本身不包含全部 ChatGPT 对话；本次已将需求原文/附件整理入工程。新对话先读交接文件，而不是假定旧对话自动变成上下文。

## 3. Mac 开发环境

源码分支不需要切换，开发环境需要准备。安装适合 Mac 架构的 Flutter/Dart，匹配项目 Dart `^3.13.2`；原机验证为 Flutter 3.47.7 / Dart 3.13.5，优先保持同一系列。Windows Flutter/Android SDK/Python venv 二进制不能直接作为 Mac 的工具使用。

macOS/iOS 构建需要 Xcode 和其命令行工具，按原生插件配置准备包管理工具并完成 SDK 初始化；用 `flutter doctor -v` 与 `flutter devices` 检查。iOS 真机还涉及开发者签名、设备信任和权限。官方入口：[macOS 设置](https://docs.flutter.dev/platform-integration/macos/setup)、[iOS 设置](https://docs.flutter.dev/platform-integration/ios/setup)。

当前 `ios/` 与 `macos/` 的 Xcode 工程已有 `FlutterGeneratedPluginSwiftPackage` 引用，未看到 Podfile，属于已有 Swift Package Manager 工程配置。先检查现有配置及插件兼容性；不要盲目新建/覆盖 Apple 工程，也不要把“有目录”当作编译验收。

环境准备好后，在保留源文件的前提下重建跨机器缓存：

```sh
flutter --version
flutter doctor -v
flutter clean
flutter pub get
flutter analyze
flutter devices
```

这些动作重建生成文件，不需要改变分支。第一次依赖恢复会依据 Mac 平台重新生成插件与 native assets；源代码、schema 迁移和已生成的 `app_database.g.dart` 不应该丢弃。需要重新生成 Drift 时使用项目现有 build_runner，不能在不了解版本时任意重生成全部内容。

随后在**隔离数据**下尝试：

```sh
flutter run -d macos
```

如报原生插件、签名、沙箱或权限问题，按问题做 Apple 平台适配；当前没有“Mac 已能运行”的证据。本次也没有 Mac 安装包。不要直接运行 Windows `fly.exe` 或 Inno Setup 脚本作为 Mac 发布方式。

Android 若继续在 Mac 开发，另装 Mac Android SDK/Java并更新本机生成的 `android/local.properties`；当前文件中的 `D:\ProgramData\flutter`、`D:\soft\sdk` 属于旧机路径，不应照抄。不要把本机路径写进业务记录。

build 38 的 Android 功能测试包沿用原电脑的测试签名。新 Mac 自动生成的 debug keystore 通常不同，不能直接覆盖旧签名应用；如需继续覆盖升级测试包，应安全迁移原测试 keystore 并配置对应签名，或先制定新签名下的数据迁移方案。keystore 不在工程 Git 内，不随客户包分发；不要为解决签名问题直接卸载丢失业务数据。正式发行签名另行配置。

## 4. 本地测试服务与官网

Windows 的 `server/.venv` 不能直接激活为 Mac 环境。使用适配的 Python 3.12 和重新建的环境安装 `server/requirements.txt`；生产仍按 `server/README.md` 用 PostgreSQL/Docker 部署，本机临时 SQLite 仅用于功能验证。

普通 `flutter test` 中真实云双客户端用例没有服务时会跳过；不能把这种结果写成“全部真实同步已验证”。若要复现包含 HTTP 的回归，可按既有测试入口在独立环境执行：

```sh
# 终端一：在 server 目录，已安装本地测试依赖的 Python 环境中
PYTHONPATH=. python tests/run_test_server.py

# 终端二：在工程根目录
FLY_SYNC_TEST_URL=http://127.0.0.1:18765/api flutter test
```

该 helper 使用临时目录和 loopback，结束后停止它并清理本次临时文件，不能连到生产数据库做测试。首次运行先确认 18765 未被别的服务占用。

`web` 是独立 PHP 官网，需要 PHP 8.2+ 和 openssl/pdo_sqlite/sodium，见 `web/README.md`。官网可本地展示；账户登录、支付适配器/价格与模块校验未齐，不开启真实销售。

## 5. Apple 平台优先检查

1. 实际架构、Flutter/Xcode/插件编译、Swift Package Manager及必要的原生依赖。
2. Documents/FlyData、文件选择、沙箱、安全存储、HTTP/HTTPS/LAN访问与权限。
3. 图片、系统打开、系统分享、通知、二维码/相机和后台生命周期；Windows专用剪贴板/拖出应有平台隔离。
4. iOS 文件目录、相机/本地网络权限、系统程序打开与分享，不能用“手机根目录公共文件夹”突破沙箱。
5. 离线授权与机器码当前偏 Windows，Mac/手机收费不能只复制注册表逻辑。
6. 使用副本验证 schema 19、完整附件和备份恢复；平台迁移不改变业务身份、删除语义或同步冲突策略。

验证、适配、签名、打包、部署是独立阶段。本次已完成 Windows / Android 功能测试包和本地提交；Apple 平台适配与实际迁移仍待新电脑执行。
