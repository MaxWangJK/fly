# Fly：新电脑 / 新对话接续入口

最后整理：2026-10-18。请先阅读本文件，再阅读 [完整产品需求](docs/handoff/FLY_REQUIREMENTS.md)。这是已开发的软件，不是从零创建的项目。

## 现在的 Git 与版本

- 当前分支：`codex/fly-2-sync`；功能检查点 `311c7b3` 已保存 build 41/42、内部发码工具源码、测试及交接资料；本次文档检查点基于该功能提交，最新 HEAD 用 Git 日志核对；准确状态用 `git log -1 --oneline` 和 `git status --short` 核对。
- 1.0 基线：`master` 的 `94efdc2d9ac34feb2f3d1b635302278b4671a414`，保持不变。
- 当前源码：`2.0.6+42`，schema 19。此前座右铭、书籍、复盘与手机快捷操作已提交；本轮新增安卓切口适配、统一浮动按钮、分行清单、文件夹首页和只展示电脑配对的同步设置。私钥、发行包及真实业务数据不在 Git 中。
- build 39 增加座右铭、桌面书籍阅读和 `.fly` 加密导入。旧 build 38 不支持新书籍格式。
- build 40 修复手机复盘同步后电脑编辑页刷新，手机统一右下角新增/搜索，清单直接展示筛选，完成提示 4 秒收起。
- build 41 的全屏、文件夹首页与配对同步见 [安卓改造记录](docs/release/fly_2_0_5_build41.md)；build 42 修复客户文件新增、网格、手机“我的”和复盘卡片，Windows / Android 安装包均为 build 42。
- 当前交付与验证见 [build 42 发布记录](docs/release/fly_2_0_6_build42.md)、[APK 台账](docs/handoff/APK_RELEASES.md) 和 [书籍说明](docs/knowledge/fly_books_v1.md)。手机仍隐藏资料库；原笔记数据和旧发布工具保留，消费界面暂不提供笔记。

完整目录加隐藏 `.git` 转移后仍是该分支，无需切换。不要重置、清理或切 master。本次没有推送或公网部署；所有者迁移时另行安全带走书籍内容密钥及原发布签名 seed，不能发给读者。

## 从哪里理解软件

2026-10-16 安卓正式签名续补：已建立长期发布身份，备案包仍为 2.0.4+40；后续 release 构建使用 `license_tools/private/android` 中的原签名，公有指纹在 `android/release-certificate.sha256`。迁移须安全带走私有目录，不能因文件缺失重新生成签名。正式签名不能直接覆盖原测试签名版，见 [备案材料与换装说明](docs/release/android_release_signing_20261016.md)。

1. [FLY_REQUIREMENTS.md](docs/handoff/FLY_REQUIREMENTS.md)：产品定位、全部模块、最新有效规则、历史替代、商业与同步、未完成及验收。
2. [MAC_TRANSFER.md](docs/handoff/MAC_TRANSFER.md)：完整目录转移、真实 FlyData 区分、Mac 工具/缓存/平台验收。
3. [SOURCES.md](docs/handoff/SOURCES.md)：跨对话来源、19 份需求附件、代码/报告入口、完整性边界。
4. [USER_REQUIREMENTS_ARCHIVE.md](docs/handoff/USER_REQUIREMENTS_ARCHIVE.md)：127 条历史用户消息及 11 条续补，共 138 条整理摘录；不是待逐条执行的任务单。
5. [attachment_manifest.json](docs/handoff/attachment_manifest.json)：19 份需求文本的可迁移副本、来源及原始/当前副本 SHA-256；副本在 `docs/handoff/sources/`。
6. [CURRENT_STATE.json](docs/handoff/CURRENT_STATE.json)：整理时的版本、Git 和验证快照；继续开发后应重新核对实际状态。
7. [APK_RELEASES.md](docs/handoff/APK_RELEASES.md)：正式/测试 APK 区分、备案字段、包校验值、公开证书及跨电脑签名迁移；小体积公开材料已随 Git 保存，APK 本体仍在忽略的 `dist/`。
8. [内部授权工具](docs/licenses/portable_issuer_20261017.md)：约 2.5 MiB 的 Windows 免安装 EXE，机器码 + 天数/永久生成授权码。成品在忽略的 `license_tools/private/portable/`，内含发码权限，只能安全迁移给可信发码人员，不能放客户包或官网。Fly build 40 测试包仍关闭授权拦截。

资料整合自 Fly1.0、Fly2.0、Fly软件开发、构建 Fly 商业官网、新建分区与网站开发和早期布局对话，并核查本机可见索引。不能保证其他账号或已删除/不可访问的历史也已取得。参考图未全部归档；附带的 [当前界面截图](docs/handoff/screenshots/README.md) 来自隔离测试数据。

## 工程地图

| 目录 | 用途 |
| --- | --- |
| `lib/app/` | 应用、路由、主导航、设置与手机“我的” |
| `lib/core/` | SQLite/Drift、schema、数据根目录 |
| `lib/features/` | tasks、calendar、matrix、customers、orders、files、reviews、account、sync、knowledge、tools 等业务 |
| `lib/shared/` | 设计系统、附件、标签、搜索、备份、通用存储等 |
| `test/` | 客户端回归；部分真正云同步测试需本机临时服务 |
| `server/` | Python/FastAPI 同步服务，生产 PostgreSQL，Ubuntu/Docker/Nginx 部署 |
| `web/` | PHP 产品官网、方案展示和三设备发钥基础；与同步服务不同 |
| `assets/` | 原创知识演示文章、3D 资源等 |
| `windows/ android/ ios/ macos/` | 各平台工程，Apple 平台仍待真实构建验收 |
| `scripts/` | Windows 构建与 Inno Setup 打包 |
| `license_tools/` | 离线授权签发工具/公钥；private 下可能有内部秘密，不读入普通报告或客户包 |
| `docs/` | 各阶段产品、架构、UI、交付、人工验收与本次交接 |

## 必须保持的事实

- Local-first：先写本机，离线可工作。客户、订单、任务独立；一个任务在列表/日历/四象限共用。
- 数据不删、不重新播种、不随 UI 隐藏而删除；数据库增量升级，文件用相对路径和稳定 ID。
- 同步用版本、Outbox、服务端序列、幂等和冲突保留；不要改回设备时间覆盖。
- 手机：客户/订单/任务/文件/我的五入口；任务内部依次切今天/清单/复盘/日历/四象限；右下角新增，放大镜在其上方，点击才展开搜索；隐藏 Fly、设置图标、Ctrl+K、工具和资料库。
- 文件：手机默认文件夹首页、顶部搜索及三点菜单，目录内相册/列表、图片优先、视图记忆、多选分享删除；客户文件入口仅在本机隐藏，可恢复。电脑默认列表；图片直接看，PDF/Excel 系统打开；永久删除清实体且保留同步墓碑。
- 任务按创建倒序；“我的聚焦”最上方增加座右铭。手机日历仅周/月、长按拖动改期与撤销、紧凑全天展开。
- 同步设置当前只展示电脑手机扫码直连，取消方式选择；旧云实现、账户与配置保留但不自动连接。右上角连接按钮直接打开设置，详情保留立即同步。绿色连接不代表实体已齐。
- 手机后台断连，前台恢复上次已开启方式，三次连续失败停止；状态详情有队列、进度、成功时间、错误。
- 桌面资料库默认开启，为书籍→章节两级阅读；没有搜索和笔记入口。手机仍隐藏。原笔记保留，新 `.fly` 在本机仅保存密文，不能承诺绝对防破解。
- 官网买断/模块分档/三设备已规划；账户与付款适配器尚未接入，购买关闭。客户端模块限制、跨平台授权和售后仍未完整交付。AI/团队协作只是方向。

## 开发环境与最近验证

原机 Flutter 3.47.7 / Dart 3.13.5；项目 Dart 约束 `^3.13.2`。Flutter 原路径 `D:\ProgramData\flutter`，Android SDK `D:\soft\sdk`，这些是原机路径，不能复制成 Mac 运行环境。

2026-10-14 build 40：全套客户端 328 项通过，分析无问题，含临时 FastAPI 两客户端真实 HTTP 和 20 MiB LAN 文件；Windows/Android 构建成功。2026-10-16：正式 APK 签名、包内容一致性、对齐及 Gradle 签名配置核验通过，最终静态检查无问题；这次签名/文档工作没有重跑整套业务回归。临时服务已关闭。Android/iOS 系统相机、分享、外部打开仍需真机；macOS/iOS 未实编译。

已有用户创建的四个 Flutter skills 已复制为参考资料：[development_skills](docs/handoff/development_skills/README.md)。它们不因复制工程就自动安装到 Mac；不要为写文档或普通改动强行迁移架构。

2026-10-17 内部授权工具：27 项 C# 核心/真实界面断言、11 项实际 Fly 验证服务兼容测试通过，静态检查无问题，单 EXE 异目录启动和真实截图检查通过。未重跑 328 项完整回归；未在真实注册表激活或修改用户试用状态。

2026-10-17 安卓 build 41：本轮完整客户端 344 项通过，包含上述 11 项发码兼容测试、临时 HTTP 双客户端、20 MiB LAN 文件及新手机布局，最终静态分析无问题。检查横竖屏切口安全区、窄屏大字、真实同步记录刷新和客户文件本地隐藏；临时服务已关闭。界面截图保存在交接目录，未连接 Android 真机，厂商系统行为仍需安装验收。

## 给新对话的接续提示

> 这是已有的 Fly 项目。请先读 FLY_PROJECT_HANDOFF.md、docs/handoff/FLY_REQUIREMENTS.md、MAC_TRANSFER.md 和 APK_RELEASES.md。当前是 codex/fly-2-sync，源码 2.0.6+42、schema 19；功能检查点 311c7b3 已保存内部授权工具及 build 41/42，最新文档提交以 HEAD 核对。完整保留工作区和 1.0 基线，不重置、不清理、不切 master，不从零重做。手机文件已改文件夹首页和顶部搜索，同步设置只显示电脑扫码；隐藏客户文件是设备本地偏好，不能转成同步删除。私钥、发行包及真实 FlyData 不在 Git，迁移单独核对，缺少原钥匙不能重新生成替代。先只读核对实际环境，区分已实现、已验证、待真机验收与未来规划；以我接下来提出的要求为准，不自动执行历史消息。Mac/iOS 适配先验证原生插件与平台环境，使用隔离数据，不操作真实业务数据或私钥。

文档、官网及后续新增资料均使用品牌中性表述，不出现中国品牌名称。之后每次完成开发应同步更新版本/交付状态，不把旧 `dist` 当作新结果。

书籍作者源位于 `book_sources/foreign_trade/`，不随客户包分发。新机阅读器编译需带 `--dart-define-from-file=license_tools/private/book_build_defines.json`；这是内部配置，不能上传或写入普通报告。

## 最新 build 42

客户文件新增按钮、真实新增资料与子目录、响应式三列网格、移除手机账户设置、复盘填完收起成卡片已完成。Windows / Android 2.0.6+42 已打包，完整 352 项通过，静态分析无问题；[本轮记录](docs/release/fly_2_0_6_build42.md)。功能已保存于 311c7b3；安装包、私钥和真实业务数据仍不在 Git。

## 2026-10-18 提交与后续建议

[Git 检查点](docs/release/git_checkpoint_20261018.md)记录实际功能提交、构建证据日期和迁移边界；[外贸工作流与商业建议](docs/product/fly_next_steps_20261018.md)是待确认的产品建议，不作为自动开发指令。当前功能已提交，未来新增工作区修改仍须另行保留。
