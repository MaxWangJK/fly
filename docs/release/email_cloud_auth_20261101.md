# 云同步邮箱注册与登录

2026-11-01。当前 2.0.7+43 / SQLite schema 20 工作区新增邮箱账号，后台迁移到 `0003`。保留此前同步与双复盘开发；本轮未提交、推送、打包或部署。云同步仍只传结构化数据，不传图片或文件内容。

## 手机和电脑流程

选择云同步后，默认显示邮箱、密码和“登录并开启云同步”。新用户选择创建账号：

1. 填写邮箱，获取后台生成的 PNG 图形验证码，输入图中四个字符；可刷新，不区分大小写。
2. 图形校验通过后发送六位数字邮箱验证码。五分钟有效，六十秒后可重新发送；重发需要新的图形验证，成功重发使旧码失效。
3. 输入邮箱码，验证通过后设置并确认密码，完成注册并自动开启云同步。

密码为 10–128 个 Unicode 字符，可用长密码，不强制特殊符号。登录直接用邮箱和密码，不重复邮箱码。错误、过期、两次密码不同、发信失败和请求过频都有反馈，并保留当前输入。

默认本地同步不变，账号表单只在云同步中出现。会话存系统安全存储，不持久化密码和邮箱验证码。工作电脑、手机和家庭电脑用同一邮箱登录后属于同一用户空间，各设备可独立撤销。

## 临时空间与账号隔离

设备接入码移入“测试入口”，仍可使用。已有临时用户在原空间选择绑定邮箱，通过同样的邮箱验证和密码设置关联原用户 ID，保留数据、游标及其他设备。

本流程不修改已验证邮箱。邮箱被另一账号使用时，不自动融合两个空间。客户端在保存会话前检查目录绑定的服务器与用户，错误账号的新会话撤销，原会话和本地记录保留。

迁移不把旧邮箱自动标记为已验证。此前默认关闭邮箱登录，主要使用临时空间；特殊的旧测试邮箱用户可由管理员签发设备接入码进入原空间，再验证绑定。原设备会话可继续用于该迁移流程。

## 发件配置与 Ubuntu

真实发件参数已配置在 **`server/private/smtp.json`**，本地后台可直接读取。此目录不进 Git、不进入 Docker 构建上下文、不进入客户端，文档不抄录授权码。迁移或部署需要安全带走该文件；只拉 Git 不会取得发件凭据。

公开模板为 [mail-settings.example.json](../../server/deploy/mail-settings.example.json)。邮件使用 SMTP SSL、465 端口、证书校验和十秒超时；正文为六位验证码，不发登录链接。最多两个并行发件操作；失败不回显 SMTP 凭据和原始异常。

在现有工程的 `server/` 中保留 `.env`、数据库与卷，安全复制私有配置后设置容器用户读取权限：

```sh
sudo chown -R 10001:10001 private
sudo chmod 700 private
sudo chmod 600 private/smtp.json
docker compose -f docker-compose.cloud.yml config --quiet
docker compose -f docker-compose.cloud.yml up -d --build
curl --fail https://world-workshop.cn/api/health
```

权限操作只用于确认后的当前 `server/private` 目录。Compose 只读挂载到 `/run/fly/private`，开启 `ALLOW_PASSWORD_AUTH=true`，保持 `CLOUD_FILE_TRANSFER_ENABLED=false`。不会另占官网 80/443；原代理步骤见 [已有官网部署](../../server/deploy/cloud_sync_20261101.md)。健康能力新增 `emailRegistration: true`。

启动执行 Alembic `0003`：新增邮箱验证时间、验证码/注册证明和限流表，不删除旧用户与业务数据。升级前备份数据库；客户端仍是 schema 20，没有新增客户端迁移。

## 校验规则

- 图形和邮箱验证码均由后台生成、校验，不接受客户端“已验证”标志。
- 验证码只存带服务端密钥的摘要。邮箱校验成功后换取十分钟有效、一次使用、绑定邮箱与用途的注册证明，设置密码时再次验证。
- 每个图形和邮箱码最多五次尝试，另有 IP/邮箱数据库限流；重启不重置发信冷却，更换图形不能绕过邮箱限制。
- 密码使用 Argon2id。验证错误响应不回显密码、验证码和票据；认证响应设 `Cache-Control: no-store`。
- 图形验证提供基础抗自动化能力，不保证完全阻挡机器人；以后可替换验证服务。邮箱码在这里验证注册所有权，不宣称它是登录多因素认证。

参考：[OWASP 认证](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)、[验证码建议](https://cheatsheetseries.owasp.org/cheatsheets/Multifactor_Authentication_Cheat_Sheet.html)、[Python SMTP SSL](https://docs.python.org/3/library/smtplib.html)。

实现：[后台邮箱流程](../../server/app/email_registration.py)、[邮件发送](../../server/app/verification_mail.py)、[API](../../server/app/main.py)、[迁移](../../server/alembic/versions/0003_verified_email_auth.py)、[客户端认证](../../lib/features/account/data/auth_service.dart)、[两端共用表单](../../lib/features/account/presentation/cloud_account_form.dart)。

## 验证与交付

- 后台全套 35 项通过，另加 SMTP 封装测试 1 项通过，共 36 个不同用例。覆盖升级保留旧数据、验证码失效与重用、发信失败、频率限制、三设备登录、临时空间绑定和云端文件接口拒绝；真实 SMTP 调用由测试替身代替。
- 客户端账号界面与服务 8 项通过；账号/双客户端协议/地址与策略/连接恢复相关 33 项通过，其中 2 项与前组重复，共 39 个不同用例。协议检查使用临时隔离后台，文件接口只在兼容性测试环境开启，生产配置仍关闭。
- 检查手机 390×844、电脑 1000×900、深色窄屏 360×780（文字 1.3 倍）和横屏 844×390；截图已人工查看。完整应用测试集没有为本功能重新全跑，也未进行真机验收。
- Flutter 静态检查通过，无问题；最终修改仅补齐条件语句的大括号。

界面留档：[电脑登录](../handoff/screenshots/cloud-email-login-desktop.png)、[手机图形验证](../handoff/screenshots/cloud-email-captcha-phone.png)、[窄屏设置密码](../handoff/screenshots/cloud-email-password-dark-narrow.png)。

测试使用隔离数据库、测试收件箱，不向真实邮箱发信。配置可读不等于已经验证实际投递；Ubuntu、域名代理和真实邮件投递在部署后验收。

本轮不含找回密码、修改已验证邮箱、注销账号、付费或支付。没有生成新 Windows/APK 或 Apple 安装包，现有 build 42 不包含该功能。
