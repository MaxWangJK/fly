# 极简匿名安装与活跃统计

2026-11-09，Fly 2.0.21+57。只实现首次安装（1）和每日启动（2），没有其他行为事件。统计的是安装实例，不是人数；同一人的电脑和手机各算一个实例，旧用户首次运行此版会产生新实例。卸载后如果配置被删除，重装可能生成新编号。

## 客户端

`lib/core/analytics/` 与业务仓库、账号和同步状态解耦。正常初始化、首帧显示后异步执行，不等待网络进入工作区。前台恢复也检查一次，成功上报的当天直接跳过；没有定时统计或复杂重试。

- `Random.secure()` 从 32 个字符中独立抽取 16 位，共 80 位随机量，不读取硬件、机器码或系统设备标识。
- 本地应用支持目录的 `anonymous-analytics.json` 保存 `analyticsDeviceCode`、`analyticsInstallReported`、`lastAnalyticsOpenDate`。该文件在业务数据目录、Fly 业务备份和同步范围之外，不随账号登录改变。手动复制整个系统配置或恢复系统备份可能保留原编号。
- 先持久保存编号，再顺序发送 1、2。1 失败仍可发送 2，服务端兼容 2 先到。
- 只有 2xx 才保存对应成功标志。4 秒超时，断网、404、500、配置失败都静默；下次启动或恢复前台再尝试，没有弹框、提示条或统计错误日志。
- 客户端按 UTC+8 判断已成功日期；服务器的日期才是统计权威。设备时钟不准可能产生少报或重复请求，后台唯一约束仍保证不会重复计数。

官方服务地址统一定义于 `lib/config/service_endpoints.dart`，默认 `https://world-workshop.cn/api`。统计有独立 `analyticsBaseUrl`，用户修改云同步服务器或选择局域网时，不会把统计发到该地址。

## 唯一协议

```http
POST /api/stats/K7M4P9X2D6QF/1
POST /api/stats/K7M4P9X2D6QF/2
Content-Length: 0
```

无 JSON、查询参数、账号令牌、日期、平台和版本。固定通用 User-Agent `Fly`。网络本身会暴露连接来源，不能声称服务器完全看不到 IP；应用不读取 IP 参与统计，也不把它或请求头写入统计表。

成功返回 200 空正文；编号限制 8–32 位 ASCII 字母数字，动作只接受 `1`、`2`，额外正文或查询参数返回 400。数据库不可用返回空正文 503。无登录依赖，后台不把随机编号关联用户。

## Schema 与并发去重

生产继续使用现有 PostgreSQL；增量迁移为 `0005_anonymous_analytics`（revision `0005`），不创建第二套后台或数据库。客户端 SQLite 仍为 schema 20。

| 表 | 字段与约束 |
| --- | --- |
| analytics_devices | device_code VARCHAR(32) 主键；first_seen_at、last_seen_at、created_at 均为 UTC 时间；first_seen_at 索引 |
| analytics_daily_active | id 大整数主键；device_code 外键仅指向统计实例；active_date DATE；created_at UTC；UNIQUE(device_code, active_date)；日期和编号索引 |

1 使用 `INSERT … ON CONFLICT DO NOTHING`，已存在不增加安装。2 先保证实例存在，再用服务器 Asia/Shanghai 日期插入活跃行；重复忽略，并单调更新 last_seen_at。数据库唯一约束负责并发安全，客户端本地成功标志进一步减少请求。两表现阶段长期保留。

100,000 个实例每天活跃会增加约 100,000 行/日，全年约 3,650 万活跃行；不能把单行很小理解为总量无限小。当前有必要索引，未作 10 万设备压测。部署后按真实数据库大小、查询延迟和备份耗时决定扩容；没有提前加入分区、缓存或外部统计系统。

## 后台与计算口径

独立管理员 HTTP Basic 认证，仅在 HTTPS 使用。配置 `ANALYTICS_ADMIN_USERNAME` 和至少 16 位 `ANALYTICS_ADMIN_PASSWORD`；默认密码空，管理路由返回 404。普通用户 JWT 不能访问。

- 页面：`GET /api/admin/stats`。
- 聚合 API：`GET /api/admin/stats/overview`，返回 `total_installs`、`today_installs`、`today_active`、`yesterday_active`、`last_7_days_active_unique`、`last_30_days_active_unique`、`retention` 和最近 30 日 `trends`。
- 全部按 Asia/Shanghai 日界线展示。WAU 为今天及之前 6 天出现过的不同编号数；MAU 为今天及之前 29 天的不同编号数，不能累加每日 DAU。
- D1、D7、D30 按 first_seen_at 的本地日期分安装 cohort，检查该日期加 1、7、30 的**那一天**是否活跃。当前卡片是全部已成熟 cohort 的加权汇总：符合观察期限的安装数作分母、精确回访数作分子。观察日未到的实例排除，没有成熟实例显示“—”，不显示假 0%。
- 页面只有九个指标卡和两个趋势图，无设备明细、模块、客户、地区、IP 等统计。无外部脚本、账号绑定或浏览行为采集，页面及接口禁用缓存。

## 日志与部署

所有 Nginx 示例增加独立 `location ^~ /api/stats/`：关闭 access_log 和该路由错误日志，清空转发来源、Cookie、Authorization，1 KiB 请求上限和 5 秒代理超时。已有 `/api/` 配置仍需补这个更精确规则。Uvicorn 同时过滤统计访问日志，包括 URL 编码形式，避免绕过 Nginx 的直连日志形成 IP 与编号的组合。应用不打印统计数据库异常参数。若你另装网关、流量分析或请求追踪，需自行对该路径关闭记录；本轮不更改真实服务器。

没有加入可持久化的 IP 限流表；可选的网关短时限流只用于防滥用，不应参与计数。匿名公开接口不能防止恶意批量伪造安装，因此指标属于使用参考，不是可审计的销售或人数数据。

详细操作：[Ubuntu 更新与验证](../server/deploy/analytics-updates.md)。主机初次安装仍用 [原生部署](../server/deploy/ubuntu-native.md)，可选 Compose 也保留，Docker 不作为必须条件。

## 维护与验证

主要文件：客户端 analytics 三文件、`startup_services_runtime.dart`、统一服务地址；后台 `app/analytics.py`、`analytics_dashboard.html`、模型和 `alembic/versions/0005_anonymous_analytics.py`。测试覆盖首次/同日/次日、失败重试、并发本地配置、超时及空协议、启动不阻塞、服务端并发唯一性、上海日界线、精确留存、管理员保护和日志抑制。

发布测试结果与范围见 [本轮交付](release/anonymous_import_updates_20261109.md)。真实服务器、真实设备跨日及 PostgreSQL 在线执行仍需部署后按指南验收，不将隔离 SQLite 测试当作生产压测。

依据：[PostgreSQL INSERT](https://www.postgresql.org/docs/16/sql-insert.html)、[FastAPI HTTP Basic](https://fastapi.tiangolo.com/advanced/security/http-basic-auth/)、[Nginx access_log](https://nginx.org/en/docs/http/ngx_http_log_module.html)。
