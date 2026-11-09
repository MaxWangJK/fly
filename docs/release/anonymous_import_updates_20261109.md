# Fly 2.0.21+57：匿名统计、简单导入与更新检查

2026-11-09。仅实现本轮三项要求，不增加其他统计事件。保留 1.0 基线、业务数据、原书籍密钥、Android 长期签名与既有同步规则。原网站和独立书稿工作区修改未纳入本轮提交。

## 交付行为

1. 正常进入应用后静默上报安装 1 和每日启动 2，随机本地编号，空正文数字协议；云端与账号不关联，失败不影响工作。后台沿用现有 FastAPI/PostgreSQL，迁移 0005，仅新增两张统计表。独立管理员凭据保护指标页、聚合接口及两幅趋势图，时区 Asia/Shanghai。
2. 新建客户弹框底部提供批量导入、Excel 模板。单表空模板，客户名称、国家、级别、状态四项必填，其他信息可选；复用导入预览、重复处理和客户业务同步。
3. 启动后台检查 Windows/Android 更新，设置“关于”支持手动检查；用户点击才下载并通过系统安装。后台从官网下载目录选择最新合规 EXE/APK；测试包与临时文件排除。

全量回归同时发现并修复既有文件名提示抢占手机长按的问题：完整文件名仍可鼠标悬停查看，触摸长按交给文件操作菜单。两个旧视觉断言改用完整名称 Tooltip 和空间稳定 ID，兼容此前文件名缩写与 A/B 区展示。

详见 [统计设计与隐私](../analytics.md)、[客户导入](../customer_import.md)、[更新机制](../app_updates.md)、[Ubuntu 部署命令](../../server/deploy/analytics-updates.md)。没有访问生产服务器、真实账号或业务库，没有发送测试统计到正式服务。

## 验证与安装包

构建源码 `2cb533947d9318065c7a79fb897e229177c32586`，版本 **2.0.21+57**。最终全量客户端 **539 项通过、3 项跳过**，本轮新增28项；跳过的是未配置真实云服务参数的三项集成场景。后台 **86项通过**（一个既有测试库弃用提示），含迁移升级/降级、旧业务保留及 PostgreSQL 离线SQL生成。最终根目录 `flutter analyze --no-pub` **No issues found**，另有lib/test/tool检查通过。初次检查扫到的独立书稿目录已从Fly分析上下文排除，书稿本身未改，不将其分析结果算作Fly结果。

首轮全量检查的两个旧视觉断言已对应文件名缩写和区域标识更新，另修复手机文件名Tooltip截获长按；最终重新跑全量通过。手机横竖屏、320宽及大字/深色的新建客户导入和更新提示通过界面测试。管理页使用示例数字在1280/390宽度检查九张卡片、两幅图及无横向溢出，预览[桌面](../handoff/windows/20261109-build57/analytics-dashboard-desktop-fixture.png)/[窄屏](../handoff/windows/20261109-build57/analytics-dashboard-phone-fixture.png)不是实际活跃数据；管理员HTTP认证、聚合及日志边界另有后台接口测试。

Windows发布构建、安装器编译、便携ZIP校验、实际EXE版本、原书籍配置、SQLite便携动态库和固定媒体SDK/许可核验通过。Ubuntu公开源码包包含0005、管理HTML、部署和测试文件，共66个文件，未包含邮件配置、虚拟环境、私钥或业务库。原生视频播放沿用build55证据，当前改动未触及播放器。

**未验证：**开发机没有Docker或Nginx，未运行Docker build/up或nginx -t；生产PostgreSQL、Ubuntu/systemd及真实服务器均未部署。Android本轮未重打，现有build50不含这三项新客户端功能；iOS/macOS未编译。Windows仍为测试授权开关关闭、安装器未作发行代码签名。

[构建清单](../handoff/windows/20261109-build57/manifest-Fly-2.0.21-build57-windows.json)。

| 文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| [Fly-Setup-2.0.21-build57-testing.exe](../../dist/Fly-Setup-2.0.21-build57-testing.exe) | 19099258 | `3F96289157B0D1813059DA2CADB43D5E96E8688128C7C62C8DBBA2A0592BA7ED` |
| [Fly-2.0.21-build57-windows-test-20261109.zip](../../dist/Fly-2.0.21-build57-windows-test-20261109.zip) | 24064140 | `A1483362132CC1623D71F1902D3958DCA07EE5EC20060C59690DC0349BDA7B2E` |
| [Fly-Sync-2.0.21-build57-ubuntu-native-20261109.tar.gz](../../dist/Fly-Sync-2.0.21-build57-ubuntu-native-20261109.tar.gz) | 80400 | `40D9AE7DEFFE2554EC6F6A4FF3AD7E480763C845604ECA4494E21C82D8AD662B` |

## 文件分布

客户端：`lib/core/analytics/`、`lib/core/updates/`、`lib/config/service_endpoints.dart`、`lib/app/startup_services_runtime.dart`，以及启动、主题提示、关于设置、客户创建/导入与本地配置入口。没有新增统计 SDK 或业务统计依赖。

后台：`server/app/analytics.py`、`analytics_dashboard.html`、`updates.py`、模型/配置/路由、`0005_anonymous_analytics.py`；四份 Nginx 示例、原生配置生成器与 Compose 发布目录只读挂载。测试新增客户端与后台对应覆盖。

## 十三项交付索引

| 项目 | 实现与入口 |
| --- | --- |
| 1. Client 修改 | [统计服务](../../lib/core/analytics/analytics_service.dart)、[持久配置](../../lib/core/analytics/analytics_storage.dart)、[启动边界](../../lib/app/startup_services_runtime.dart)、[更新服务](../../lib/core/updates/update_service.dart)、更新提示/设置、客户创建及导入；完整分布见上文 |
| 2. Backend 修改 | [统计路由](../../server/app/analytics.py)、[管理HTML](../../server/app/analytics_dashboard.html)、[更新路由](../../server/app/updates.py)、模型/配置、0005、Nginx和部署配置 |
| 3. DeviceCode | Random.secure，16位无易混字符Base32，80位随机量；先保存到本地应用支持目录，无硬件读取 |
| 4. Action 1 | 未成功则发送数字1，2xx才标记；后台安装主键冲突忽略，下次打开重试失败上报 |
| 5. Action 2 | 按上海日期本地去重，发送数字2，2xx才保存日期；服务端生成统计日，允许先到2 |
| 6. Schema | analytics_devices(code主键、三个UTC时间)；analytics_daily_active(id、code、date、UTC时间)，日期与编号索引；[详细结构](../analytics.md) |
| 7. 当日去重 | 客户端成功日期 + PostgreSQL UNIQUE(device_code, active_date)，并发ON CONFLICT DO NOTHING |
| 8. Retention | 安装本地日加1/7/30的精确当日回访；排除未成熟cohort，按成熟安装数加权；WAU/MAU为唯一编号 |
| 9. Admin | GET /api/admin/stats 与 /api/admin/stats/overview；独立HTTP Basic，仅HTTPS使用，默认空密码关闭 |
| 10. Nginx | /api/stats/独立更精确规则，保留路径转发18766、关闭日志和来源头；原PHP与其他API规则保留 |
| 11. Tests | 上方最终客户端、pytest与Alembic结果；3项真实云集成缺配置跳过，非生产验收 |
| 12. Flutter Build | Windows release、实际版本与原书籍配置/媒体库核对、Inno安装器和ZIP完整性；Android本轮未构建 |
| 13. Ubuntu | [完整命令](../../server/deploy/analytics-updates.md)：备份、覆盖公开源码、保留私有配置、执行原生安装脚本、迁移0005、nginx -t、curl验证；Docker仅可选且本机未验证 |

## 边界

统计是安装实例数，不是人数或历史总安装；匿名接口不阻止人为伪造。两张表长期保留，有索引，未作十万设备压测。更新服务不自动执行安装，也不代替原发行签名；首个支持检测的版本需手动安装。Android 源码支持，不在本轮重新打包；iOS/macOS 更新分发未加入。Docker/Nginx/生产 PostgreSQL 与真实 Ubuntu 验收待执行，不能以本机测试标记成功。
