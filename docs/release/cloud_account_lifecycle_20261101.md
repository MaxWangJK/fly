# 云同步账号生命周期

后续部署补充：现已提供含这些账号接口的 [原生 Ubuntu 后台源码包](native_backend_20261101.md)，不依赖 Docker；客户端仍未重新打包。下面“本轮”描述的是账号功能开发阶段。

2026-11-01，build43 之后的源码续补，客户端仍使用 `2.0.7+43` / SQLite schema20，后台 Alembic 升级为 `0004`。本轮没有提交 Git、打包或部署；现有 build43 Windows、Android 和 Ubuntu 后台包不含本次功能。官网独立修改未改动。

## 手机与电脑操作

登录页增加“忘记密码”。已验证云账号在同步设置中增加“修改密码”和“注销云端账号”；保持手机“我的”原有入口，不重新引入独立账户设置菜单。

找回/修改密码：邮箱 → 图形验证 → 六位邮箱码 → 新密码及确认。密码为 10–128 个字符。成功后返回普通登录，保留云端用户 ID、客户、任务、订单与复盘等记录，撤销全部旧设备、访问/刷新会话、未使用设备接入码和旧验证证明。邮件补发密码重置通知；通知投递失败不会撤销已完成的重置。其他设备在下次请求发现会话失效后清除本机登录状态。

注销：先说明范围，邮箱固定为当前已验证账号，完成图形验证和六位邮箱码，输入当前密码并勾选确认后才能提交。永久删除在线账号、设备/令牌/接入码、同步记录、变更历史、冲突候选、幂等记录和旧云文件索引；不影响其他账号。云同步仍不传图片或文件内容。

注销后清除本机登录，关闭云同步，保留本机业务数据库、文件、待同步队列及旧账号目录绑定；本地/局域网仍可使用。不能把原目录自动切给新账号，避免把原数据意外传入另一个账号；需要其他账号时使用独立数据目录。

旧云实体文件使用持久清理任务；普通情况立即完成，存储暂不可用时提示后台清理，并在服务启动及每分钟重试，每批最多 20 个账号。任务只保存用户 ID 与时间，完成即删除。注销后旧令牌立即失效，清理重试不会恢复账号。管理员维护的外部备份按保留策略另行处理，本接口不连接或删除外部备份。

## 接口与保护

共用基础地址 `https://world-workshop.cn/api`。原官网 PHP 路由不变，无需新增 Nginx location。

| 接口 | 请求与行为 |
| --- | --- |
| `POST /auth/registration/captcha` | `email`、`purpose`：register / bind / reset / delete。bind/delete 要求会话；delete 只允许当前账号邮箱。 |
| `POST /auth/registration/send-code` | `challengeId`、`captcha`，返回六十秒重发间隔，邮件注明操作用途。 |
| `POST /auth/registration/verify-code` | `challengeId`、六位 `code`，换取一次性 `verificationTicket`。 |
| `POST /auth/password/reset` | `email`、`password`、`confirmPassword`、reset 专用 `verificationTicket`，成功返回 `ok`、`signInRequired`、`notificationSent`。 |
| `POST /account/delete` | Bearer、当前 `email`/`password`、delete 专用 `verificationTicket`、`confirmation: "DELETE"`，返回 `ok`、`localDataPreserved`、`fileCleanupPending`。 |

图形码及邮箱码各五分钟，最多五次猜测；证明十分钟、一次使用，绑定邮箱、用途和必要的用户 ID。发送六十秒冷却、每邮箱每小时五次，验证每邮箱每小时十五次；注销另限每用户十分钟五次。IP 和邮箱限流持久化，HMAC 计数标识不保存明文邮箱，旧窗口定期清理。找回请求不查询邮箱是否存在，已注册与未注册邮箱经历相同的验证请求；只有拥有邮箱并完成验证才能进入最终恢复判断，不会自动创建账号。

全部账号接口禁止缓存，不回显密码、验证码或令牌。客户端仅接收允许列表内的固定错误原因。工作区行锁协调重置、注销、登录、刷新和已认证请求，防止旧会话在注销/重置后重新取得有效令牌。

流程参考 [OWASP Forgot Password Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html)：一次性且限时的恢复凭据、确认新密码、普通流程重新登录及撤销旧会话。应用没有新增登录依赖或第三方推送。

## 部署与验收

按 [Ubuntu 共存部署](../../server/deploy/cloud_sync_20261101.md) 备份后上传完整最新 `server/` 源码，保留 `.env`、`private/`、卷和签名/密钥配置，重建原 Compose 服务；启动自动运行 `alembic upgrade head`。`alembic current` 应为 `0004`，健康接口应有 `passwordReset=true`、`deleteAccount=true`。只使用旧 build43 后台压缩包无法获得这些接口。

迁移 `0004` 仅新增 `account_deletion_cleanup`，不改客户端 schema、不批量删除任何已有账号。业务删除只由对应账号完成验证并明确确认后触发。真实 SMTP、Ubuntu 和物理手机验收未执行；自动测试使用隔离数据库、临时文件及假邮箱，不调用真实账号删除。

最终验证结果见 [CURRENT_STATE.json](../handoff/CURRENT_STATE.json) 的 `accountLifecycleVerification`；本轮不将 build43 的全量 405 项测试记作新功能通过证据。

## 本轮验证结果

客户端账号、同步工作区、通知、断点续传相关 34 项通过，后台全量 49 项通过，Flutter 静态检查无问题。新账号功能包含 9 项客户端用例，后端已覆盖重置后的旧密码/会话/设备码失效、注册证明不能跨用途、错误密码与注销确认、删除其他账号隔离、存储失败后重试，以及迁移保留旧记录。

手机 390×844、电脑 1000×900、深色窄屏 360×780 / 1.3 倍文字及横屏 844×390 均走通，已查看并归档三张界面截图。使用现有注册测试回归，不改旧复盘或业务数据。全量客户端 405 项是 build43 历史记录，本轮没有重跑全量客户端；本轮测试中的现有 Drift 内存库调试提示及 Starlette 依赖弃用提示没有导致失败。

日志在被忽略的 `.buildlog/account-lifecycle-*-final.log`。没有实际发邮件、部署、生成安装包或验证物理设备、生产 PostgreSQL 并发。
