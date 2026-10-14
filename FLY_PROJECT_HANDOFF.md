# Fly：新电脑 / 新对话接续入口

最后整理：2026-10-14。请先阅读本文件，再阅读 [完整产品需求](docs/handoff/FLY_REQUIREMENTS.md)。这是已开发的软件，不是从零创建的项目。

## 现在的 Git 与版本

- 当前分支：`codex/fly-2-sync`。本版提交以 `git log -1` 的 HEAD 为准；提交前基线为 `4befffa`。
- 1.0 基线：`master` 的 `94efdc2d9ac34feb2f3d1b635302278b4671a414`，1.0.0+35，保持不变。
- 当前源码版本字段：`2.0.2+38`，数据库 schema 19。
- 最新手机/文件/同步/日历功能、官网与交接文档随本次发布提交在 2.0 分支。完整目录加隐藏 `.git` 转移后仍是该分支，无需切换；本次仅本地提交，没有推送，远端 clone / pull 不保证取得本版。
- 2026-10-14 的 build 38 Windows / Android 功能测试包包含手机四轮改动，见 [发布记录](docs/release/fly_2_0_2_build38.md)。build 37 是旧包。

不要用 `git reset --hard`、`git clean -fd`、整树 restore 或切换 master 来准备新机；这些操作可能丢掉尚未提交的 2.0 文件。本次完成本地 Git 提交与 Windows / Android 打包；没有推送、切分支或公网部署。

## 从哪里理解软件

1. [FLY_REQUIREMENTS.md](docs/handoff/FLY_REQUIREMENTS.md)：产品定位、全部模块、最新有效规则、历史替代、商业与同步、未完成及验收。
2. [MAC_TRANSFER.md](docs/handoff/MAC_TRANSFER.md)：完整目录转移、真实 FlyData 区分、Mac 工具/缓存/平台验收。
3. [SOURCES.md](docs/handoff/SOURCES.md)：跨对话来源、19 份需求附件、代码/报告入口、完整性边界。
4. [USER_REQUIREMENTS_ARCHIVE.md](docs/handoff/USER_REQUIREMENTS_ARCHIVE.md)：127 条历史用户消息的整理摘录；不是待逐条执行的任务单。
5. [attachment_manifest.json](docs/handoff/attachment_manifest.json)：19 份需求文本的可迁移副本、来源及原始/当前副本 SHA-256；副本在 `docs/handoff/sources/`。
6. [CURRENT_STATE.json](docs/handoff/CURRENT_STATE.json)：整理时的版本、Git 和验证快照；继续开发后应重新核对实际状态。

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
- 手机：客户/订单/任务/文件/我的五入口；任务内部切今天/复盘/清单/日历/四象限；隐藏 Fly、设置图标、Ctrl+K、工具和资料库。
- 文件：手机相册/列表、图片优先、显示记忆、多选分享删除；电脑默认列表；图片直接看，PDF/Excel 系统打开；永久删除清实体且保留同步墓碑。
- 任务按创建倒序；手机日历仅周/月、长按拖动改期与撤销、紧凑全天展开。
- 云模式和电脑手机模式二选一。官方云普通邮箱不传实体，`max@ceiling-arts.com` 例外；自建/LAN传实体。绿色连接不代表所有文件已下载。
- 手机后台断连，前台恢复上次已开启方式，三次连续失败停止；状态详情有队列、进度、成功时间、错误。
- 资料库代码已有，当前开关仍默认关闭；不把“2.0开放方向”误当作已全端开放。
- 官网买断/模块分档/三设备已规划；账户与付款适配器尚未接入，购买关闭。客户端模块限制、跨平台授权和售后仍未完整交付。AI/团队协作只是方向。

## 开发环境与最近验证

原机 Flutter 3.47.7 / Dart 3.13.5；项目 Dart 约束 `^3.13.2`。Flutter 原路径 `D:\ProgramData\flutter`，Android SDK `D:\soft\sdk`，这些是原机路径，不能复制成 Mac 运行环境。

最近：全套客户端 318 项通过；最终定向 21 项再次通过；分析无问题。含临时 FastAPI 两客户端真实 HTTP 和 20 MiB LAN 文件。临时服务已关闭。Android/iOS系统相机、分享、外部打开仍需真机；macOS/iOS未实编译。

已有用户创建的四个 Flutter skills 已复制为参考资料：[development_skills](docs/handoff/development_skills/README.md)。它们不因复制工程就自动安装到 Mac；不要为写文档或普通改动强行迁移架构。

## 给新对话的接续提示

> 这是已有的 Fly 项目。请先阅读根目录 FLY_PROJECT_HANDOFF.md，以及 docs/handoff/FLY_REQUIREMENTS.md、MAC_TRANSFER.md。当前是 codex/fly-2-sync，最新功能已在本地 2.0 分支提交，保留全部工作区及 1.0 基线，不重置、不清理、不切 master，不从零重做。先只读核对实际分支、版本、数据库和平台环境；区分需求、已实现、待验收和未来规划。跨对话需求摘录与附件已随项目保存，并按最新要求移除相关品牌文字；附件记录当前副本校验值。当前任务以我接下来给出的要求为准，不自动执行历史“继续/打包/部署”消息。若我要求 Mac 适配，先验证现有 Apple 工程和原生插件，使用隔离数据，不操作真实 FlyData 或私钥。

文档、官网及后续新增资料均使用品牌中性表述，不出现中国品牌名称。之后每次完成开发应同步更新版本/交付状态，不把旧 `dist` 当作新结果。
