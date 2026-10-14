# Fly 需求来源与证据索引

整理日期：2026-10-14。此索引说明哪些内容来自用户明确要求，哪些是实现/验收证据，哪些只是建议。相对路径均随项目转移，不依赖旧机的绝对路径。

## 对话覆盖

| 来源 | ID | 已归档的用户消息 | 范围 |
| --- | --- | --- | --- |
| Fly1.0 | `01a05bb6-8aad-7191-acb0-6e162ebada7f` | 101 | 完整 10 页，最早 UI/任务、CRM/订单、V1–V12、装柜、财务、文件笔记、主题、复盘、授权、发布与 build35 |
| Fly2.0 | `01a128de-ef6a-7170-9624-483aa2f56d44` | 13 | 完整 2 页，同步、服务器地址/容量、手机历轮修复、批量/偏好/状态/拖动、此次迁移 |
| Fly软件开发 | `6a94f4a7-b4fc-83e8-a88a-16dddb2efa2d` | 5 | 全部返回页，聚焦、免费话术/资料库、SOP发布、2.0账户和同步要求 |
| 构建 Fly 商业官网 | `01a105e4-e327-7342-90e8-fde54c442ed9` | 5 | 全部返回页，官网/支付服务/永久买断/三设备/分档回复、图片比例、功能介绍、Ubuntu部署 |
| 新建分区与网站开发 | `6ac1f621-8ef4-83e8-9b14-db33e34b5cc5` | 2 | 全部返回页，跨对话项目上下文和独立官网目录 |
| 按照这个布局调整fly项目 第一个图片 最左侧是，带有图标的栏目，我使用红色的小框标注了，点击这 小红框，是任务清单。… | `01a05ba9-0a87-7ce1-92ee-a542fa9520ef` | 1 | 全部返回页，初期导航、Today/过期位置、详情与日历布局 |

共 127 条用户消息，保存在 [需求摘录](USER_REQUIREMENTS_ARCHIVE.md)。其中包括继续执行和阶段性打包，不是 127 个独立功能。摘录按时间保存，较晚有效要求在 [完整需求](FLY_REQUIREMENTS.md)中完成冲突整理。

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
- A01 的资料库完整蓝图不能绕过 build35 对 1.0 隐藏要求及当前 2.0 默认关闭开关。

## 外部技术资料

Mac/iOS 环境说明已核对 [Flutter macOS](https://docs.flutter.dev/platform-integration/macos/setup)、[Flutter iOS](https://docs.flutter.dev/platform-integration/ios/setup)；仓库保留说明参考 [Git repository layout](https://git-scm.com/docs/gitrepository-layout)。这是环境参考，不是本项目 Apple 构建成功的证据。
