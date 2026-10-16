# Fly 2.0.3 build 39：座右铭与书籍阅读

2026-10-16 接续说明：本页保留 2026-10-14 构建时的历史状态；build 39/40 源码及书籍作者源现已纳入本次本地检查点。当前版本为 2.0.4+40，另有正式安卓签名备案包，最新状态见 [项目交接](../../FLY_PROJECT_HANDOFF.md) 和 [APK 台账](../handoff/APK_RELEASES.md)。

2026-10-14；当前 2.0 分支 `codex/fly-2-sync`，源码 `2.0.3+39`，schema 19。1.0 master 基线保留。本次改动尚未提交，源码基线为 `6b59521`；迁移必须带走当前工作区，不只复制旧 Git 提交。本次没有公网部署。

## 交付

| 文件 | 大小 |
| --- | --- |
| [Fly-Setup-2.0.3-build39-testing.exe](../../dist/Fly-Setup-2.0.3-build39-testing.exe) | 12.72 MiB |
| [Fly-2.0.3-build39-windows-test-20261014.zip](../../dist/Fly-2.0.3-build39-windows-test-20261014.zip) | 15.60 MiB |
| [Fly-2.0.3-build39-android-test-20261014.apk](../../dist/Fly-2.0.3-build39-android-test-20261014.apk) | 89.28 MiB |
| [Fly-Foreign-Trade-Fieldbook-v1.fly](../../dist/Fly-Foreign-Trade-Fieldbook-v1.fly) | 0.11 MiB |

[安装与导入说明](../../dist/README-Fly-2.0.3-build39-testing-20261014.md)。Windows 安装版直接运行，便携版完整解压再运行 fly.exe。需要 Microsoft Visual C++ x64 与 Microsoft Edge WebView2 运行库。Android 7.0+，含三个处理器架构，签名与 build 38 相同，可覆盖升级。

## 使用

1. 先更新到本次 Windows 39 版。
2. 打开资料库，从右上角“导入 .fly 书籍”选择 `Fly-Foreign-Trade-Fieldbook-v1.fly`。
3. 按章节阅读；下次使用继续阅读或阅读历史。可以标记本章已读。build 38 不支持这一格式。
4. 任务→我的聚焦的最上方是我的座右铭，点击编辑，离开编辑框自动保存，原人生主线在下面。

桌面资料库仅书籍与章节两个层级，不显示第三层列表、搜索或笔记入口。原笔记未删除。手机资料库仍隐藏，本次 Android 包更新座右铭；原客户/订单/任务/文件/我的导航不变。

第一版外贸手册 16 章、约 1.5 万文本字符，以现有 14 篇原创资料整理，附原创插图、背景、练习和工作表；没有另外一份完整私人笔记稿，没有使用真实客户或订单数据。作者后续可直接编辑 [HTML/CSS 源稿](../../book_sources/foreign_trade/README.md) 后重新发布。

## 内容保护

`.fly` 是带 AES-256-GCM 与 Ed25519 签名的加密格式，不是换后缀 ZIP。导入只保存密文，不生成供读者浏览的 HTML/CSS/图片目录；图片只在 HTML 中显示。阅读器不提供素材导出或单独图片打开，禁用包内脚本和远程资源。内部配置文件、发布 seed、作者源与私有调试符号没有放入安装包。

客户端必须解密才能显示，所以不能保证绝对防破解；专业逆向、内存抓取、截图/OCR仍可能获取内容。部分旧原始示例资料本来就是已公开的素材，不能因重新编入书籍而成为保密内容。保护细节、格式限制与迁移见 [书籍说明](../knowledge/fly_books_v1.md)。

## 验证

- 完整客户端回归 325 项通过，含隔离 FastAPI 双端 HTTP 同步及 20 MiB LAN 实体文件；测试服务及临时数据库已关闭清理。
- 静态分析无问题，新增书籍加密、错误密钥/篡改/脚本拒绝、更新保护、密文单文件存储、阅读进度重启恢复、历史、座右铭与旧笔记草稿/编辑验证通过。
- 已实际检查书架宽/窄布局、座右铭位置和 HTML 的字体、段落与嵌入图片；截图使用隔离数据，浏览器预览来自与阅读器相同的文档生成器。
- Windows Release 与安装器编译通过，版本信息为 2.0.3+39；便携包完整性、相对 SQLite 绑定、编译配置与作者密钥对应关系核对通过。
- Android Release、APK完整性、版本/最低系统/三架构与签名验证通过。构建中的 Kotlin/SDK 工具兼容提示仍需在以后升级 SDK 时复查。

两端测试包关闭本地试用限制；正式 Windows 脚本仍保持原收费授权参数，并要求原书籍内部配置，不会静默构建出无法导入书籍的发行包。Windows 未做发行代码签名，Android 沿用测试签名。系统真机功能仍需用户验收；Apple 平台未构建。阅读进度暂存本机，不做云同步。

## 校验

- `Fly-Setup-2.0.3-build39-testing.exe`：`A89E5C7935A9A3C1B006E2778C859B07E4889CD54BF0E90F83857C719C394E98`
- `Fly-2.0.3-build39-windows-test-20261014.zip`：`D48FA26053371C7ED91262460B5C9A80DA64CE4F41F799FC047B57A430B45145`
- `Fly-2.0.3-build39-android-test-20261014.apk`：`FC27C47613E83D97CC8FD97500D927E9F44E5F30750CA9E4D69EA1C972E0EC6A`
- `Fly-Foreign-Trade-Fieldbook-v1.fly`：`7C27E28E1E687487F8F51EC0D353CF02FDD154B87C0916976BA38ACD956A1EB1`

每个文件旁有对应 `.sha256.txt`；重新构建或发布书籍后应重新计算。
