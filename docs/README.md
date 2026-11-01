# Fly Documentation

当前交付入口：[2.0.7 build43](release/fly_2_0_7_build43.md)、[云同步策略和 API](architecture/cloud_sync_runtime_20261101.md)、[Ubuntu 详细部署与现有 Nginx 合并](../server/deploy/cloud_sync_20261101.md)。历史安装包说明仍保留在下方，最新产物以本轮报告和 APK 台账为准。

2026-11-01：[云同步邮箱注册、登录、临时空间绑定及 SMTP 配置](release/email_cloud_auth_20261101.md)。云端仍不传文件内容；真实发件凭据随私有目录独立迁移。

2026-11-01 新复盘：[基础/航向双方案与实现边界](product/review_compass_20261101.md)、[收费建议（尚未实施）](product/monetization_20261101.md)。原复盘和卡片保留，进阶当前开放体验，不接支付。

跨对话需求、状态及 Mac 迁移入口：[项目交接](../FLY_PROJECT_HANDOFF.md)、[完整需求](handoff/FLY_REQUIREMENTS.md)、[来源及附件](handoff/SOURCES.md)。当前 Windows / Android 见 [2.0.6 build 42](release/fly_2_0_6_build42.md)，此前安卓改造见 [build 41](release/fly_2_0_5_build41.md)。

Fly is a Windows-first, cross-platform-ready, local-first task manager.

安卓备案与后续发布签名：[2026-10-16 正式签名材料](release/android_release_signing_20261016.md)、[APK / Windows 包校验及迁移台账](handoff/APK_RELEASES.md)。公开备案信息、公钥、证书和清单已纳入 Git，安装包及私钥仍另行转移。

内部免安装发码工具：[2026-10-17 使用与迁移说明](licenses/portable_issuer_20261017.md)。只有机器码及天数/永久参数，工具本体拥有发码权限，仅供所有者保管。

- `product/`: vision, V1 boundaries and roadmap
- `architecture/`: technical decisions, data flow, database, state and routing
- `design/`: visual system and responsive desktop behavior
- `research/task_app_reference/`: sanitized architecture lessons from the reference study

Runtime behavior is documented from Fly source and tests. Research documents contain knowledge only and are not runtime dependencies.

书籍与座右铭： [2.0.3 build 39](knowledge/fly_books_v1.md)，作者源位于 [book_sources](../book_sources/foreign_trade/README.md)。

2026-10-18：[Git 检查点与迁移边界](release/git_checkpoint_20261018.md)、[外贸工作流、市场参照及后续建议](product/fly_next_steps_20261018.md)。建议尚未转为确认的开发排期。

2026-10-18 文件移动：[手机与电脑单文件/批量移动说明](release/file_move_20261018.md)，源码已实现，现有 build 42 安装包尚未更新。

2026-10-31：[客户和订单字段标题](release/crm_list_columns_20261031.md)、[GitHub 上传记录](release/github_upload_20261031.md)。

2026-10-31：[LocalSend 源码与局域网同步评估](research/localsend_evaluation_20261031.md)。结论是保留现有 Fly 协议，本轮不引入 LocalSend；列明加密、下载续传及传输调度的后续建议和真实验证范围。

2026-11-01：[多设备自动同步、下载续传与云接入](release/sync_multi_device_20261101.md)、[已有官网的 Ubuntu 部署及三设备场景](../server/deploy/cloud_sync_20261101.md)。当前源码 2.0.7+43、schema 20，未重新打包或线上部署。
