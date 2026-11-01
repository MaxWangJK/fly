# Fly 2.0 同步基础

> 当前 2026-11-01 多设备自动合并、临时设备码、云端数据同步与本地下载续传，以 [2.0.7 开发记录](release/sync_multi_device_20261101.md) 为准；以下是历史阶段记录。

> 下文记录 2.0.0+36 初始实现。2.0.1+37 的两种模式、扫码、自动文件同步和手机布局更新，以 [手机与同步修复](fly_2_0_1_mobile_fixes.md) 为准。

1.0 基线：`94efdc2`，独立开发分支：`codex/fly-2-sync`。2.0 版本号 `2.0.0+36`。
本次没有修改原有未提交的 `.gitignore`、`docs/marketing/`、`web/` 工作。

## 本地优先与升级

数据库版本 17 → 18 增量迁移；不替换业务表、主键或外键，不清空旧数据。
所有业务操作仍先写本地 SQLite，登录只是同步能力，未登录或服务端不可用不阻止原业务功能。
默认同步关闭，首次启用显示本机客户、订单、任务、笔记、文件数量，并合并到登录账号。

同步元数据采用 `sync_metadata` 侧表，主键 `(entity_type, record_key)`，包含 `sync_id`、`sync_version`、`local_updated_at`、`deleted_at`、`sync_status`、持久 JSON 快照。业务 UUID、内置固定键、日期键及复合关系键均保留原格式。
协议 syncId 是固定命名空间下 `UUIDv5(table + ':' + JSON(primaryKeyValues))`，首次准备传输时写入侧表；重复登录、备份恢复、多设备内置记录采用相同身份。原有业务 version 不是同步版本。

SQLite AFTER INSERT/UPDATE/DELETE 触发器在原语句事务内维护元数据和 `sync_outbox`。关系硬删除也保留墓碑。事务回滚同时撤销业务与队列。非设备字段更新进入队列，未发送同记录编辑合并，已发送请求正文固定用于安全重试；同记录最多一个 mutation 在途。
同步记录按表名标识，覆盖下列 46 个表：

```text
app_settings (仅 themeMode / locale / colorPalette)
dashboard_focuses dashboard_focus_histories dashboard_daily_focuses daily_reviews
file_folders file_tags file_tag_links
note_folders workspace_notes knowledge_favorites note_blocks note_tag_links
task_lists tasks tags task_tags checklist_items reminders
customer_categories customer_statuses customer_sources customers customer_contacts
customer_notes customer_custom_field_definitions customer_custom_field_values
customer_follow_ups customer_tag_links
order_statuses orders order_notes factories products order_production_items
order_payments order_cost_entries order_tag_links order_files attachments
container_presets cargo_packages loading_plans loading_plan_groups
container_sections section_cargo_entries
```

通知投递日志、数据目录、令牌、缩略图路径、文件的设备路径和打开时间不进入云端。官方知识包仍在原来的签名资源系统中，用户收藏及笔记关联可以同步。

## 引擎与冲突

业务队列 → 幂等 push → ack 事务 → 按 server seq 分页 pull → 本地 apply / cursor 事务。实际 blob 先上传，以保证接受的文件元数据及冲突副本可获取内容。
后端 workspace 行锁保护版本和提交顺序；本地业务时钟只用于显示。删除优先；明确 restore 才恢复。
远端应用抑制触发器回声，通过 Drift 通知更新原有页面。待发本地字段覆盖远端同次拉取，仍保留原 mutation 供服务器裁决；远端删除不被普通离线修改自动复活。
跨分页外键引用写入 `sync_incoming` 后才推进游标，父记录到达后重试。未能应用的外键/唯一值冲突会显示同步失败，不静默丢弃记录。
同字段冲突存两个候选；同笔记块创建另一份块副本；同附件二进制保留 canonical 与冲突文件副本。设置页可以选择保留当前、另一份或显式恢复。

启动、恢复前台、登录启用、WebSocket 收到数据变更提醒及每 5 分钟补查会触发云同步。业务修改约 250 ms 合并网络请求；同步中再次触发会保留后续轮次。WebSocket 只是唤醒信号，每 30 秒空闲心跳保持连接，心跳不触发数据拉取。断线按 2–60 秒退避重连；手机进入后台断开，回前台立即补查。系统后台推送暂未开发，见 [当前协议与后续计划](architecture/cloud_sync_runtime_20261101.md)。

## 文件与局域网

云端/局域网分别有文件内容开关，默认关闭。关闭时文件元数据、文件夹、标签、关系仍同步；预览显示“文件内容仅存在于其它设备”。
文件流式哈希、4 MiB 上传分片、恢复 offset、用户内哈希去重、`.part` 下载和校验后重命名。旧版没有 SHA-256 的文件在开启文件同步后增量补齐；外部编辑在上传前检测并生成元数据修改。远端 canonical 替换本机字节前将旧字节保存在 `files/conflicts/`。

桌面内置 Dart HTTP host，无需安装 Python。默认 8765、IPv4 内网地址、5 分钟六位配对码、每 IP 5 次/分钟尝试、随机设备令牌哈希及撤销。支持双向、电脑→手机、手机→电脑，记录方向在服务端强制，客户端协商后保留不发送的本机队列。当前 LAN 前台约 2 秒补查；遇地址改变先发现已配对主机，手机连续三次失败停止自动重试，可手动重连。
云端开启时 LAN 禁用记录版本协调，避免两个 coordinator 分叉，LAN 文件接口仍可用。

## 当前边界和待验收项

- 一个本地数据目录绑定一个同步工作区。切换不同账号/服务器或纯 LAN 与 cloud coordinator，需要独立数据目录；当前没有工作区重新绑定/版本迁移向导。
- 同时开启 cloud 与 LAN 时，已配对客户端可以独立开启 LAN 文件内容传输；云端记录版本仍只有一位协调者。当前先运行云文件队列再运行 LAN 文件队列，没有按实时带宽动态选择下载线路。
- 云端记录始终双向同步；LAN 方向用于纯 LAN 同步，不约束云端记录。组合模式的附加 LAN 文件队列当前双向运行。
- Bootstrap 基于持久日志分页，尚无历史压缩或服务端快照。已验证 35,000 条变更分页无遗漏；真实 PostgreSQL 吞吐、长期历史增长仍需压测。
- LAN 没有 QR / mDNS；使用代码配对和上次地址重连。
- Android/iOS/macOS 网络权限基础已配置，XML/plist 结构已检查；这些平台的构建及实机权限尚未验收。本阶段优先 Windows。
- 冲突展示两份 JSON 文本，没有富文本行级 diff。跨设备相同标签唯一值冲突暂留待应用队列并报告，不会自动改名。
- Docker、真实 PostgreSQL 并发锁、Ubuntu HTTPS 部署以及两台真实设备手工验证，需在具备该环境时验收；本机不能代替这些检查。

部署命令、环境变量、Nginx、TLS、备份与升级见 `server/README.md`。

## 后端结构与认证

后端准确目录：`E:\workSpace\fly\server`。`app/main.py` 提供 FastAPI 路由，`models.py` 定义 SQLAlchemy 模型，`sync.py` 处理原子版本合并，`storage.py` 封装按用户隔离的磁盘 blob；`alembic/` 保存增量迁移。部署使用 Python 3.12、PostgreSQL 16、单 API worker、Nginx TLS，当前不依赖 Redis。

九张服务端表：`users`、`devices`、`refresh_tokens`、`sync_records`、`sync_changes`、`processed_mutations`、`sync_conflicts`、`file_blobs`、`file_upload_sessions`。生产 JSONB、BIGSERIAL 游标；客户端通过 mutationId、recordId 和 baseVersion 交互，所有查询按认证 userId 隔离。

邮箱 trim/lowercase，密码使用 Argon2id；JWT 20 分钟，refresh token 30 天、哈希保存、旋转和设备撤销。Flutter 通过系统安全存储保存会话，服务器与本地数据目录分别隔离。错误信息不会显示请求正文或令牌。尚未实现邮箱验证、忘记密码重置、账号删除和收费；能力标志明确返回未支持。

Android 自动备份/设备迁移规则排除安全存储令牌与密钥缓存，业务数据备份规则继续使用系统默认值。macOS 使用私有 legacy Keychain，以免为单应用会话存储引入额外 Keychain Sharing 分发配置；实机验收仍待执行。

HTTP 请求禁用自动重定向；WebSocket 握手使用独立连接工厂，按 scheme/host/port 限制为已配置服务器同源，TLS 使用系统证书验证，登录首帧不会发送到跨源重定向目标。

## Ubuntu 与域名部署入口

`server/README.md` 含从配置 `.env`、申请证书、启动容器、检查健康到备份/恢复/升级的逐条 Ubuntu 命令。`server/deploy/nginx.conf` 是 `world-workshop.cn` 完整示例；`server/deploy/install.sh` 可在 Docker、DNS、密钥已配置后运行：

```bash
cd /opt/fly/server
chmod +x deploy/install.sh
./deploy/install.sh YOUR_REAL_EMAIL
```

本次没有连接或部署公网服务器，也没有更改 DNS。

## 验证记录

- 后端：13 项测试通过，覆盖账户、用户隔离、令牌轮换/撤销、幂等、字段合并、冲突副本、删除及恢复、文件恢复/哈希、输入约束和 35,000 条分页。Alembic SQLite 升降级及 PostgreSQL 离线迁移 SQL 已验证；这不能替代真实 PostgreSQL 执行。
- Flutter 静态检查：0 issues；完整回归 253 项通过，包含真实 HTTP 两客户端测试，没有以跳过代替此项验收。
- 同步专项：11 项通过，含事务/outbox、17→18 保留数据、远端回声抑制、游标回滚、冲突状态、LAN 配对/方向，以及 1000/390 宽度设置页；另增 WebSocket 正常收发及跨源重定向拒绝 2 项回归检查。
- 两客户端：两套独立 Flutter SQLite 数据库连接实际本机 FastAPI HTTP 服务，完成同账号注册/登录、Jack 新建及地址传播、离线 phone/address 自动合并、同字段候选保留、Tom 联合集合、删除优先、文件元数据独立同步以及启用内容后 SHA-256 文件可读取。此项包含在专项统计中。
- Windows release：最终构建通过，包含 WebSocket 同源保护。程序为 `E:\workSpace\fly\build\windows\x64\runner\Release\fly.exe`；分发时需要整个 Release 目录的 DLL 和 data 资源，不可只复制 exe。
- Docker/Compose/Ubuntu/真实 PostgreSQL/真实双设备验收仍列为待执行，未标记 PASS。

## 后续：服务器地址兼容与资源规划

支持公网/内网 HTTP、HTTPS、域名、IPv4、IPv6 和自定义端口；省略协议采用 HTTP，省略 `/api` 自动补齐。HTTPS 仍验证证书，HTTP 仍保持用户选择，不进行自动降级。自定义代理前缀须提供以 `/api` 结尾的实际路由。Apple ATS 已允许自定义 HTTP，但原生验收仍待执行。

新增 `server/docker-compose.http.yml` 与 `server/deploy/nginx-http.conf` 提供无需证书的 IP/HTTP 部署；注册/登录保留限流，已登录会话刷新不共用该限流。服务器 Host 白名单支持 IP/域名/IPv6，拒绝未配置的主机。

本次 Flutter 专项 38 项通过，静态检查 0 issues；覆盖地址归一化、默认端口、实际 IPv6 WebSocket、心跳忽略、设置界面和同步基础。更新后的 Windows release 构建通过。Apple plist 与两份 Compose YAML 结构检查通过，但未执行 Apple 实机或 Docker 部署。

后端完整回归 15 项通过，新增空闲心跳后继续接收变更、IP/域名/IPv6/端口白名单检查。依赖一致性检查通过；测试客户端存在 Starlette 对 httpx 的弃用提示，无测试失败。

真实 2 核 4 GB 服务器仍未压测。6 Mbps、约 20 MB 文件的理论带宽及设备规划见 `docs/fly_2_server_capacity.md`，50→100 台是验收目标，不能作为容量保证。
