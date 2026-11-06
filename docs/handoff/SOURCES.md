# Fly 需求来源与证据索引

整理日期：2026-11-02。此索引说明哪些内容来自用户明确要求，哪些是实现/验收证据，哪些只是建议。相对路径均随项目转移，不依赖旧机的绝对路径。

## 对话覆盖

| 来源 | ID | 已归档的用户消息 | 范围 |
| --- | --- | --- | --- |
| Fly1.0 | `01a05bb6-8aad-7191-acb0-6e162ebada7f` | 101 | 完整 10 页，最早 UI/任务、CRM/订单、V1–V12、装柜、财务、文件笔记、主题、复盘、授权、发布与 build35 |
| Fly2.0 | `01a128de-ef6a-7170-9624-483aa2f56d44` | 43（历史 13 + 续补 30） | 历史完整 2 页加当前续补；同步、手机修复、迁移、书籍、备案、授权工具、文件浏览、复盘、邮箱账号生命周期及原生自行部署 |
| Fly软件开发 | `6a94f4a7-b4fc-83e8-a88a-16dddb2efa2d` | 5 | 全部返回页，聚焦、免费话术/资料库、SOP发布、2.0账户和同步要求 |
| 构建 Fly 商业官网 | `01a105e4-e327-7342-90e8-fde54c442ed9` | 5 | 全部返回页，官网/支付服务/永久买断/三设备/分档回复、图片比例、功能介绍、Ubuntu部署 |
| 新建分区与网站开发 | `6ac1f621-8ef4-83e8-9b14-db33e34b5cc5` | 2 | 全部返回页，跨对话项目上下文和独立官网目录 |
| 按照这个布局调整fly项目 第一个图片 最左侧是，带有图标的栏目，我使用红色的小框标注了，点击这 小红框，是任务清单。… | `01a05ba9-0a87-7ce1-92ee-a542fa9520ef` | 1 | 全部返回页，初期导航、Today/过期位置、详情与日历布局 |

历史 127 条，加当前清理发布、座右铭/书籍及手机交互 3 条续补，共 130 条用户要求，保存在 [需求摘录](USER_REQUIREMENTS_ARCHIVE.md)。其中包括继续执行和阶段性打包，不是 127 个独立功能。摘录按时间保存，较晚有效要求在 [完整需求](FLY_REQUIREMENTS.md)中完成冲突整理。

2026-10-16 又补入安卓备案获取、iOS 备案字段和正式安卓签名三条要求，总计 133 条。正式签名说明见 [备案材料](../release/android_release_signing_20261016.md)，必须保留私有发布身份供新电脑继续构建。

随后补入“提交 Git 信息，并完善需求文档到之前的迁移文档中，以及 APK 信息”，现为 127 条历史消息 + 7 条续补，共 134 条。本次检查点保存后续代码和文档，公开 APK 材料已复制到 [apk/20261016](apk/20261016/README.md)，最新包及签名核验见 [APK 台账](APK_RELEASES.md)。私钥和安装包仍被忽略，没有推送或部署。

2026-10-17 新增免安装发码 EXE 要求，累计 135 条。实现与边界见 [内部工具说明](../licenses/portable_issuer_20261017.md)、[可复现源码](../../license_tools/portable_issuer/README.md)，本次源码/测试/文档属于 `24afa8d` 之后未提交工作区，成品单独保管在私有忽略目录。

随后新增安卓适配、浮动按钮、完整清单、默认周视图、文件夹首页及只显示扫码同步六项要求，累计 136 条。当前实现见 [build 41](../release/fly_2_0_5_build41.md)，覆盖旧“四模块浮动搜索”和“同步模式二选一”界面规则；仍保留旧云实现和业务数据。

本轮补入客户文件新增按钮、每排至少三个文件夹、手机移除账户设置及手机/电脑复盘卡片四项要求，累计 137 条，见 [build 42](../release/fly_2_0_6_build42.md)。历史“我的包含账户设置”已被覆盖；新客户普通资料与原业务附件区分保存，不改旧附件归属。

另读取“商业授权与签名”（`6abcbed3-5174-83e8-a256-5faa13cbb026`）所返回的助手答复；接口没有返回对应用户问题。只用于识别安装器许可、代码签名与真实环境验收的讨论背景，不采纳其中旧版本测试数、服务价格或地区资格作为当前事实，也不将助手建议变为用户新指令。

检索还覆盖本机 Codex 对话索引与当前归档列表，没有发现额外相关 Codex 归档。工具可见性仍有限：其他账号、未同步/已删除会话或未被返回的 ChatGPT 历史无法保证覆盖。部分参考图片/思维导图没有随历史正文返回；未声称已经归档全部原图。

## 原始需求附件

19 份历史文本均找到并复制，部分副本已按最新要求进行品牌中性化整理。详细原路径、副本位置、原始与当前副本 SHA-256 和行数见 [attachment_manifest.json](attachment_manifest.json)。下表链接是可迁移副本。

| 编号 | 主题 | 文本 |
| --- | --- | --- |
| A01 | V12 Knowledge Hub / SOP | [需求副本](sources/prompt-c50eb22e-91e0-481f-97fe-c748dd4f7360.txt) |
| A02 | Dashboard Focus Board | [需求副本](sources/prompt-adf875e8-1686-4317-b8e9-f8d933f2573a.txt) |
| A03 | Polish V11 | [需求副本](sources/prompt-43cb11fd-c711-4881-9dc0-5597ec777e99.txt) |
| A04 | Polish V10 Tasks/CRM/Files/Notes/Review/3D/License/语言 | [需求副本](sources/prompt-8efc1db8-b4ae-4958-a25b-0f7de7da2777.txt) |
| A05 | Polish V8 导航/时间/设置 | [需求副本](sources/prompt-0903c77d-0133-4168-a415-c9bada9566c3.txt) |
| A06 | 装柜 V2 | [需求副本](sources/prompt-7f044929-ad01-4ec6-953f-df7131c25577.txt) |
| A07 | 3D 装柜初始规划 | [需求副本](sources/prompt-636f1ef6-dda0-465e-9521-c48f668d5d3d.txt) |
| A08 | V7 数据/搜索/提醒/附件/导入/Dashboard | [需求副本](sources/prompt-4c226662-b071-4e66-ad99-8e10872ab3ea.txt) |
| A09 | Polish V6 财务/导出/主题 | [需求副本](sources/prompt-3739fe00-02c3-42d8-b5d7-72c0dd0b56fa.txt) |
| A10 | CRM/Orders V5，后续再次提供 | [需求副本](sources/prompt-ecdcb44d-0296-4749-9514-2d54d2173b9f.txt) |
| A11 | CRM/Orders V5 | [需求副本](sources/prompt-1564e07f-b8a3-4582-884d-4f96671be47c.txt) |
| A12 | CRM/Orders V4 | [需求副本](sources/prompt-cc0f2202-46a1-477d-95a3-531c1106324f.txt) |
| A13 | CRM/Orders V3 | [需求副本](sources/prompt-0a5c0acf-bbe9-421c-8f9a-4f8c7ce3dcb0.txt) |
| A14 | CRM/Orders V2 微调 | [需求副本](sources/prompt-63deb0e8-b32f-43c0-afef-aaaed1360f68.txt) |
| A15 | CRM/Order 微调 V1 | [需求副本](sources/prompt-d40d8281-0fe0-42fc-b96b-d56cef621e4f.txt) |
| A16 | UI/UX V4 | [需求副本](sources/prompt-3cfc0a12-1b27-46f4-878d-a8fcc4e11fb2.txt) |
| A17 | V1 UI/UX 重构 | [需求副本](sources/prompt-ff5f21e8-57ec-49b7-8dae-bf0148cddbb9.txt) |
| A18 | V1 UI/UX 最初提供 | [需求副本](sources/prompt-93d4a658-cd37-4a10-901d-2693057f1103.txt) |
| A19 | Fly2.0 Account/Cloud/LAN/Backend | [需求副本](sources/prompt-ebc95c50-5b76-49cd-976f-19c60ec6425e.txt) |

两个直接写在对话内的长提示词另存为 [CRM/Orders V2](sources/prompt-crm-orders-v2-inline.txt) 和 [V9 文件/笔记](sources/prompt-files-notes-v9-inline.txt)，整理摘录也保留在归档中。

## 模块依据

| 模块 | 关键资料 / 代码 |
| --- | --- |
| 1.0 发布边界 | [v1_scope](../product/v1_scope.md)、[build35](../release/fly_1_0_build35_final.md) |
| 架构与数据库 | [overview](../architecture/overview.md)、[database](../architecture/database.md)、`lib/core/database/` |
| 任务/日历/四象限 | [任务状态](../design/task_visual_states.md)、[calendar_spec](../design/calendar_spec.md)、[matrix_spec](../design/matrix_spec.md)、`lib/features/tasks/`、`lib/features/calendar/`、`lib/features/matrix/` |
| CRM/标签 | [filter_semantics](../crm/filter_semantics.md)、[today_followup](../crm/today_followup_query.md)、[next_action](../crm/followup_next_action.md)、`lib/features/customers/` |
| 订单/财务 | [V6](../reports/fly_polish_v6_final_report.md)、[V7](../reports/fly_v7_final_report.md)、`lib/features/orders/domain/order.dart` 与 data/presentation |
| 文件/笔记 | [V9](../reports/fly_v9_progress.md)、[Windows拖出](../files/windows_drag_out.md)、[备份对象](../files/backup_v9.md)、`lib/features/files/`、`lib/features/notes/` |
| 资料库 | [publishing](../knowledge/publishing.md)、[build30](../release/fly_v12_knowledge_build30_report.md)、`lib/features/knowledge/`、`assets/knowledge/seed/` |
| 聚焦/复盘/主题 | [build34](../release/fly_1_1_build34_focus.md)、[build33](../release/fly_1_1_build33_palette.md)、`lib/features/dashboard/`、`lib/features/reviews/` |
| 装柜 | [V4](../reports/container_loading_v4_report.md)、[V5](../reports/container_loading_v5_report.md)、[V6](../reports/container_loading_v6_report.md)、[坐标](../tools/container_loading/coordinate_system.md)、`lib/features/tools/container_loading/` |
| 同步与手机 | [foundation](../fly_2_sync_foundation.md)、[第一轮](../fly_2_0_1_mobile_fixes.md)、[第二轮](../fly_2_mobile_experience_fixes.md)、[第三轮](../fly_2_mobile_interaction_round3.md)、[第四轮](../fly_2_mobile_interaction_round4.md) |
| 容量 | [capacity](../fly_2_server_capacity.md)，其中早期监听/组合开关描述按最新手机文档覆盖 |
| 后端 | [server README](../../server/README.md)、`server/app/`、`server/tests/`、`server/alembic/` |
| 官网 | [web README](../../web/README.md)、[Ubuntu部署](../../web/deploy/ubuntu-24.04.md)、`web/src/catalog.php`、`web/src/Core.php`、`web/tests/smoke.php` |
| 离线授权 | [local_license](../licenses/local_license_v10.md)、`lib/shared/licensing/`、`license_tools/public_key.txt`，不读取私钥内容 |
| 自定义开发规范 | [skills副本](development_skills/README.md) |
| 当前视觉 | [截图索引](screenshots/README.md) |

上表是模块入口，部分跨目录代码由 shared 组件提供。历史报告中的版本/测试数只证明当时情况；最新状态见 [CURRENT_STATE.json](CURRENT_STATE.json) 和主需求文档，不把报告中的“当时未完成”或“旧设计”机械套回当前版本。

## 需要特别注意的旧文档

- `docs/orders/simple_financial_currency.md` 是 V5 简化阶段；当前订单模型和 V6/V7 已包含原始币种与 RMB 利润转换。
- `docs/tools/container_loading_v3.md` 的 100mm 悬出被 V4 的 1000mm 规划阈值替代。
- 同步基础文档的独立文件开关、无码配对、同时云+LAN、1秒/20秒本地合并等被手机后续要求修改；看最新 round3/round4。
- 第二轮文档中的手机默认列表、五种日历视图、工具/资料库在“我的”入口，被第三轮的新要求替代。
- `README.md` 下半部分是原 1.0 说明；新机接续以根目录交接入口为先，不误判当前仍只有 Windows local-only。
- A01 的资料库完整蓝图不能绕过 build35 对 1.0 隐藏要求及最新桌面两级书籍阅读规则；手机资料库仍隐藏。

## 外部技术资料

Mac/iOS 环境说明已核对 [Flutter macOS](https://docs.flutter.dev/platform-integration/macos/setup)、[Flutter iOS](https://docs.flutter.dev/platform-integration/ios/setup)；仓库保留说明参考 [Git repository layout](https://git-scm.com/docs/gitrepository-layout)。这是环境参考，不是本项目 Apple 构建成功的证据。

## 当前书籍续补依据

[书籍说明](../knowledge/fly_books_v1.md)、[作者源](../../book_sources/foreign_trade/README.md)、[build 39](../release/fly_2_0_3_build39.md)。现有 14 篇原创 Markdown 整理为 16 章；已只读检查当前笔记标题与空关联笔记，以及不存在单独导入的官方包，未读取真实客户或订单。build 39/40 源码和作者源已保存到本次检查点，私有书籍配置仍须另行转移。

手机交互最新续补见 [build 40](../release/fly_2_0_4_build40.md)：复盘编辑刷新、右下角新增与搜索、内嵌清单筛选、完成提示计时及导航顺序。它覆盖旧手机共用搜索/新建输入框和仅底部清单选择的要求。

2026-10-18 新增 Git/文档及产品建议要求，累计 138 条。功能检查点 `311c7b3` 已保存此前源码；[市场与开发建议](../product/fly_next_steps_20261018.md)引用当日查阅的 HubSpot、Bigin、Pipedrive 官方功能/套餐和国际贸易署单据说明，并明确没有真实访谈/活跃/付费数据。建议不是确认的需求。

2026-10-18 又补入手机长按/电脑右键图片移动至指定文件夹或根目录的要求，累计 139 条。见 [实现说明](../release/file_move_20261018.md)；该源码续补未重新打包，不能把旧 build 42 当作已含新入口。

同日新增检查并开发批量移动的明确要求，累计 140 条。检查结果为原多选栏没有移动入口，本次补上；使用现有归属保护和同步，见 [移动说明](../release/file_move_20261018.md)。

2026-10-31 补入客户/订单列表字段名称，以及上传到用户指定 GitHub 仓库的要求，当时累计 141 条需求摘录。实现与本轮 17 项针对性检查见 [列表说明](../release/crm_list_columns_20261031.md)；远端状态见 [上传记录](../release/github_upload_20261031.md)。

2026-11-01 本聊天续补三条来源（LocalSend 研究、三设备与云同步开发、接入码确认），以本轮消息及 [开发记录](../release/sync_multi_device_20261101.md) 为准；没有扩大其他聊天可访问范围。

同日新增双复盘与收费建议一条，累计 145 条；参考了本轮用户提供的四张图片，未将图片或原作者文字纳入应用素材。原创实现见 [航向复盘](../product/review_compass_20261101.md)，收费建议独立标注为尚未实施的方案。

同日邮箱注册登录和继续执行两条，累计 147 条。用户参考代码中的真实授权码没有复制进公开档案、应用或构建上下文，迁移时单独安全带走 `server/private`。流程和验收见 [邮箱记录](../release/email_cloud_auth_20261101.md)。

同日新增前台立即/定时云同步、提交打包与 Ubuntu 共存部署一条，以及用户明确自行部署、只需详细文档的一条，累计 149 条。依据本轮消息、当前 PHP 路由及 [协议](../architecture/cloud_sync_runtime_20261101.md)/[部署指南](../../server/deploy/cloud_sync_20261101.md)，未访问真实 Ubuntu 或发送真实邮件。

同日补入找回密码/注销账号要求和继续执行两条，累计 151 条（127 历史 + 24 续补）。依据当前用户消息、源码与隔离测试，见 [账号生命周期](../release/cloud_account_lifecycle_20261101.md)。未连接真实邮箱或删除真实账号；build43 成品不包含这次源码续补。

同日增加服务器无法下载 Docker、数据库与 Python 独立部署并简化流程一条，累计 152 条（127 历史 + 25 续补）。依据用户说明和现有后端配置，原生方案见 [部署指南](../../server/deploy/ubuntu-native.md)；没有扩大服务器访问范围，没有改动独立官网工作区。

同日增加客户必填单选、基础复盘保留、平面文件浏览、“我的”资料及账号、自建服务器隐藏默认地址、互斥同步确认、手机单表头等七项优化一条，累计 **153 条（127 历史 + 26 续补）**。用户同时授权提交全部工作区及打包，包含之前保留的官网下载页修改。代码、验证和包信息见 [build44](../release/fly_2_0_8_build44.md)。

2026-11-02增加客户右键填写PI创建订单、订单六阶段、文件夹随图标视图一条，累计154条（127历史+27续补）。用户本轮明确授权提交并推送Git及打包Windows/安卓，见[build45](../release/fly_2_0_9_build45.md)。


2026-11-02补入移除设备接入码、顶部头像更新、Fly扫码图解与隐藏文件检查一条，现累计155条（127历史+28续补）。仅作为本轮有效要求，不将历史阶段要求再次执行；[交付记录](../release/fly_2_0_10_build46.md)。


2026-11-06补入PVC数量修改后剩余空间不可见一条，累计156条（127历史+29续补）。以最新TOOL-13和[修复记录](../release/container_spaces_20261106.md)为准。


2026-11-06补入数量清空未实时计算、货物直接移除一条，累计157条（127历史+30续补），见[交付](../release/cargo_quantity_20261106.md)。
