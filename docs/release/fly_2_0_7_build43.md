# Fly 2.0.7 build43：云账号与多设备同步

2026-11-01；SQLite schema20、后台迁移0003，分支 `codex/fly-2-sync`，1.0 master 基线保持不变。本轮将此前工作区功能与当前调度改造一起归档、构建；实际提交、验证及产物校验结果在本文末尾记录。

## 本轮交付内容

- 云同步：已启用账号启动、恢复前台即同步，新增/修改/删除约 250 ms 合并后发送；WebSocket 变更提醒、每 5 分钟兜底，保留同步中再次触发，连接退避重试。手机后台断开；默认仍是本地同步，云端所有账号均不传图片或文件内容。
- 邮箱账号：后台图形验证、六位邮箱码、设置并确认密码；邮箱密码登录，原临时空间可绑定邮箱保留数据。发件配置只在后台私有文件，不进 Git 或客户端。
- 三设备：工作电脑/手机/家庭电脑按稳定身份、字段版本自动融合，保留离线独立新增及审计；LAN 文件续传、传输调度、已配对地址发现与重连继续可用。
- 双复盘：基础免费默认方案与原创航向复盘并存，旧复盘和卡片保留；进阶可浏览和体验，支付未接入。先前文件移动、批量移动及客户/订单表头也包含在新包。
- Ubuntu：独立后台与原 PHP 官网共域名；保留官网 `/api/checkout`、`/api/activate`，提供完整 Nginx、详细步骤、不会覆盖既有配置的生产初始化工具及公开后台交付包。用户自行部署，未操作真实主机。

测试包继续关闭本地授权拦截，沿用原书籍配置和安卓正式/测试签名，不重新生成身份。Windows 安装器未作发行代码签名。Android 两种签名不能互相覆盖升级，按原安装版本选择；换装前保留完整备份，新 schema20 不要用旧 build42 打开。

部署时还需安全转移 `server/private/smtp.json`，公开后台包不包含它。当前仅在隔离环境验证，不把本机通过等同于 Ubuntu、公网、真实 SMTP 或手机系统已验收。Apple 未构建。

## 开发与使用入口

[云同步调度与 API](../architecture/cloud_sync_runtime_20261101.md)、[详细 Ubuntu 步骤](../../server/deploy/cloud_sync_20261101.md)、[完整 Nginx](../../server/deploy/world-workshop.nginx.conf)、[邮箱流程](email_cloud_auth_20261101.md)、[复盘](../product/review_compass_20261101.md)、[APK 台账](../handoff/APK_RELEASES.md)。

## 本机代理配置验证

官方便携 Nginx 1.30.6 对配置完成语法和 8 项 HTTP/TLS/WebSocket 检查：保留官网入口，两个 PHP API 的 POST/正文/原 URI 仍正确，HTTP 跳转、同步前缀、WebSocket 升级与首帧、原隐藏文件及 PHP 规则通过。只替换了回环端口、测试路径、临时证书与 PHP/API 替身，测试后已关闭进程；不代表 Ubuntu 或真实官网业务已验收。


## 已完成验证与提交

- 源码提交 `55bd11da84281ae650648967490562660bdfe0fb`；打包时应用/后台源码无未提交差异。交付文档与哈希在后续文档提交归档；官网页脚的独立本地改动保留，不属于本次源码提交。
- 完整客户端 **405 项通过**，包含临时双/三设备后台、云模式恢复和手机前后台、改动即时发送及同步中追加、WebSocket 重连取消、邮箱流程、双复盘及原业务场景。后台全套 **41 项通过**；最终静态检查无问题。
- Windows release、安装器、便携 ZIP 与 Android release 构建成功。SQLite 相对绑定、原书籍配置、必需运行库、ZIP/APK 完整性、安卓原正式/测试证书、16 KB 对齐及两种 APK 的非签名内容一致均已核验。
- 公开 Ubuntu 包来自上述提交，包含初始化、迁移、Nginx 及详细步骤；不含 SMTP、环境秘密、数据库、venv 或业务数据。源码与客户包检查未发现真实发件授权码。
- 临时后台已关闭；没有推送远端、修改真实 Ubuntu/Nginx、发送真实邮件、安装/卸载用户软件或执行 Apple 构建。Nginx 目标机语法与公网链路、邮件投递、二维码/相机/分享/外部打开仍按部署和真机步骤验收。

## 交付文件

| 文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| [Fly-Setup-2.0.7-build43-testing.exe](../../dist/Fly-Setup-2.0.7-build43-testing.exe) | 13,453,780 | `D7FB0893809327114CDCDA7029392BE536418EDCF6C239FCC19D31D778B96792` |
| [Fly-2.0.7-build43-windows-test-20261101.zip](../../dist/Fly-2.0.7-build43-windows-test-20261101.zip) | 16,068,120 | `1886E49FF4C8132159FE527A4521217BBB8130CF7113E738C1A025A8063977FE` |
| [Fly-2.0.7-build43-android-release-signed-20261101.apk](../../dist/Fly-2.0.7-build43-android-release-signed-20261101.apk) | 94,633,956 | `D483D504B5B1587459493669144CC7569EA70AC8C6D3A2CB9C885C63EC3DDEAC` |
| [Fly-2.0.7-build43-android-test-20261101.apk](../../dist/Fly-2.0.7-build43-android-test-20261101.apk) | 94,634,216 | `A2AA832024906F271F61650FDA469B195B99CCBC41D444C5AF7CD80C509DF704` |
| [Fly-Sync-2.0.7-build43-ubuntu-20261101.tar.gz](../../dist/Fly-Sync-2.0.7-build43-ubuntu-20261101.tar.gz) | 218,326 | `FF6E5D806C31B2FB8C5CB01A96284EFC39E43F9A66622E0F9257E030629799DB` |

[公开机器可读清单](../handoff/apk/20261101/manifest-Fly-2.0.7-build43.json)、[安卓备案字段](../handoff/apk/20261101/Fly-Android-Release-Filing-Info-build43.txt)。正式/测试签名包按已有安装身份选择，不能混用覆盖升级。
