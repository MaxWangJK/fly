# Fly 2.0 Sync Backend

**当前推荐部署：**[Ubuntu 原生简化部署](deploy/ubuntu-native.md)。PostgreSQL 单独安装，Python 使用虚拟环境与 systemd；上传代码和私有发件配置后执行 `sudo bash deploy/install-native.sh`。无需 Docker，继续使用现有 Nginx、PHP 官网及 `127.0.0.1:18766`。下文容器部署保留为历史可选方式。

2026-11-01 当前源码：邮箱注册、登录、找回/修改密码和注销云账号已加入，支持图形验证、六位邮箱码，以及临时空间绑定邮箱保留数据。迁移已到 `0004`，新增注销后的持久文件清理任务。build43 成品只含到 `0003`，本轮源码尚未重新打包。密码登录默认开启，云端仍不传图片/文件内容。真实发件参数仅存被忽略的 `private/smtp.json`，运行时只读挂载，见 [邮箱配置](../docs/release/email_cloud_auth_20261101.md)、[账号生命周期](../docs/release/cloud_account_lifecycle_20261101.md)。已有官网请使用 [共存部署](deploy/cloud_sync_20261101.md)，后面的旧“设备码阶段/邮箱关闭”说明以本段及新文档为准。

后端目录：`E:\workSpace\fly\server`。已有官网的 Ubuntu 部署使用 `/opt/fly-sync/server`，详见上方共存部署；云端调度与 API 请求形状见 [协议说明](../docs/architecture/cloud_sync_runtime_20261101.md)。

Python 3.12 容器、FastAPI、SQLAlchemy 2、PostgreSQL 16、Alembic；Redis 不参与核心协议。Starlette 最低版本为 1.7，以采用可校验 IPv6 Host 的解析器。
SQLite 仅用于隔离测试，不替代生产 PostgreSQL。

## 协议与存储

- `POST /api/sync/enroll-device`：管理员为同一用户空间的每台设备签发一次性码，默认 15 分钟有效，数据库仅存码哈希，一次消费并按 IP 限流；公开接口不能自报用户 ID。
- `/api/auth/register|login|link-email`：后台图形与六位邮箱码验证后注册，邮箱密码登录；已有临时空间可绑定邮箱保留用户 ID。`/api/auth/refresh|logout`：20 分钟 JWT、30 天设备独立刷新令牌，哈希存储、轮换和撤销。
- `/api/account/me`、`/api/devices`、`/api/devices/{id}/revoke`：全部按认证用户隔离。
- `POST /api/auth/password/reset`：reset 专用邮箱证明及确认新密码；保留原用户 ID/业务数据，撤销全部旧设备与令牌，需重新登录。
- `POST /api/account/delete`：已验证账号的会话、delete 专用证明、当前密码与 `confirmation=DELETE`；永久移除该用户云端数据，本机数据不受影响。旧云文件清理失败后排队重试；表 `account_deletion_cleanup` 仅保留待清理用户 ID 与创建时间，完成即移除。
- `POST /api/sync/push`：最多 200 条。`mutationId` 幂等，重复 ID 的不同内容返回 409。整个批次提交或回滚。
- `GET /api/sync/pull?after=0&limit=100`：变更日志游标，最多 200 条、约 4 MiB/页。每条记录最多 1 MiB。
- `/api/sync/bootstrap`：采用同样的持久变更日志分页，客户端折叠记录历史。当前实现没有快照压缩，首次同步会读取历史变更。
- `/api/sync/conflicts` 与旧 resolve 路由保留兼容；当前重叠候选自动归档为已处理，客户端不要求人工选择。
- 以下文件接口是兼容/隔离测试能力，当前云部署默认全部返回 403；没有特殊邮箱例外。
- `/api/files/upload/init`、`PUT /api/files/upload/{id}/chunk?offset=...`、`POST /api/files/upload/{id}/complete`：4 MiB 分片、7 天可恢复会话、SHA-256、单文件 2 GiB 上限。用户内去重，临时文件 `.part` 校验后原子重命名。
- `/api/files/{fileId}/download`：通过受保护的文件元数据获取 blob，文件名不参与服务器路径构建。
- `/api/ws`：接受后第一帧传 JWT，随后发 `sync_available/latest_cursor` 及空闲心跳。不在 URL 中传 token。每 2 秒检查持久日志，断线后仍以 HTTP 游标拉取为准。
- `/api/health`：数据库连接检查，返回状态、API 版本、服务端时间与自动合并/设备接入/文件内容能力。

服务端使用 users 行锁串行化同一用户的 push，包含首次记录创建。全局 seq 的用户子序列按提交顺序可见，避免并发事务的游标跳过。记录版本独立于客户端本地业务 version 和设备时钟。
不同业务字段自动合并；`updated_at` 和本地 `version` 不参与冲突判断。同字段按因果版本、字段毫秒修改时间与稳定变更 ID 自动取舍，限制过大的未来时钟，并保留已归档候选；旧编辑不会仅因晚到覆盖新值。独立订单号/唯一标签重名自动附短编号，保留各自 ID 和关联。删除优先；恢复必须显式使用当前墓碑版本。附件二进制并发保留原 canonical 并创建冲突文件副本；笔记块并发保留另一块副本。

表：users、devices、refresh_tokens、device_enrollment_codes、email_auth_challenges、auth_rate_buckets、sync_records、sync_changes、processed_mutations、sync_conflicts、file_blobs、file_upload_sessions。JSON 在 PostgreSQL 使用 JSONB。
`app/schema_v1.py` 是迁移 0001 的冻结定义；以后变更新增 Alembic revision，不修改冻结定义。

## 历史：独立占用网站端口的 Ubuntu 部署（已有官网请用上方新流程）

先安装 Docker Engine 与 Compose 插件，参考 [Docker Ubuntu 安装文档](https://docs.docker.com/engine/install/ubuntu/)。DNS 将 `world-workshop.cn` 的 A 记录指向服务器，开放 TCP 80/443。数据库和 API 不发布到公网。

```bash
sudo mkdir -p /opt/fly
# 将本仓库 server 目录上传到 /opt/fly/server
cd /opt/fly/server
cp .env.example .env
chmod 600 .env
openssl rand -hex 32
# 将输出填入 JWT_PRIVATE_SECRET；生成另一个随机值设置 POSTGRES_PASSWORD，
# 同步修改 DATABASE_URL 中的密码（建议只使用 hex，避免 URL 转义问题）。
nano .env
mkdir -p deploy/certbot deploy/letsencrypt
docker compose up -d --build postgres api
```

首次 TLS 证书签发（此时 nginx 尚未启动，80 端口可用）：

```bash
cd /opt/fly/server
docker run --rm -p 80:80 \
  -v "$PWD/deploy/letsencrypt:/etc/letsencrypt" \
  -v "$PWD/deploy/certbot:/var/www/certbot" \
  certbot/certbot certonly --standalone --agree-tos \
  --email YOUR_REAL_EMAIL -d world-workshop.cn
docker compose up -d nginx
curl --fail https://world-workshop.cn/api/health
docker compose ps
```

`deploy/nginx.conf` 提供完整域名示例，HTTP 跳转 HTTPS，注册/登录共享 IP 限流，WebSocket 转发，8 MiB 请求上限。会话刷新不与密码登录共用此限流，避免同一办公出口下的已登录设备重连受到影响。

完成 Docker、DNS 和 `.env` 配置后，也可用安装脚本完成构建、首次证书签发和健康检查：

```bash
cd /opt/fly/server
chmod +x deploy/install.sh
./deploy/install.sh YOUR_REAL_EMAIL
```
API 容器使用一个 worker，进程内限流加 nginx 限流。代理头只应来自 compose 内部 nginx；不要将 8000 直接公开。
`.env` 示例没有可用生产密钥，部署前必须替换。`ALLOWED_HOSTS` 和 `CORS_ORIGINS` 按实际域名设置。CORS 不启用 credentials，不使用不受限 wildcard。

证书续期：配置 Ubuntu systemd timer 定期运行以下命令，并监测失败；无需停止 nginx。

```bash
cd /opt/fly/server
docker run --rm \
  -v "$PWD/deploy/letsencrypt:/etc/letsencrypt" \
  -v "$PWD/deploy/certbot:/var/www/certbot" \
  certbot/certbot renew --webroot -w /var/www/certbot
docker compose exec nginx nginx -s reload
```

## IP、域名、自定义端口与 HTTP

客户端支持 `http://IP:端口`、`https://IP:端口`、HTTP/HTTPS 域名、IPv6（例如 `http://[::1]:8080`）。省略 `/api` 会自动补齐。2.0.1 起，界面默认显示 `world-workshop.cn/api` 并使用 HTTPS；自建地址可以省略协议，测试连接会尝试适用的 HTTP/HTTPS 并保存成功的协议。反向代理前缀可以填写完整的 `https://域名/前缀/api`。实际服务必须提供相应路由。

HTTP 使用 `ws` 通知连接，HTTPS 使用 `wss`；默认端口分别为 80/443。HTTPS 使用系统证书校验，IP 访问需要证书包含该 IP，自签证书需由设备信任，不会自动绕过证书错误。HTTP 密码、令牌和业务数据不加密，公网建议 HTTPS；客户端保留用户选择。

纯 HTTP/IP 部署无需证书，可以使用独立 compose 文件：

```bash
cd /opt/fly/server
# 在已经填写数据库密码与 JWT 随机密钥的 .env 中追加/修改：
nano .env
# HTTP_PORT=8080
# ALLOWED_HOSTS=你的真实服务器IP,你的域名,localhost,127.0.0.1
# 主机名不带协议、路径或端口；IPv6 白名单填写无方括号的实际地址。
docker compose -f docker-compose.http.yml config --quiet
docker compose -f docker-compose.http.yml up -d --build
curl --fail http://127.0.0.1:8080/api/health
```

在防火墙/安全组开放所选 TCP 端口。客户端填 `http://真实IP:8080` 即可。此配置仍只发布 Nginx；数据库和 API 保持内部端口。不要同时启动同一项目的 HTTPS 与 HTTP 两套 compose 文件；选择一套。

HTTPS 自定义端口可将原 compose 的 `443:443` 改为 `8443:443`，客户端使用 `https://域名:8443`；若保留 HTTP 重定向，将 Nginx 跳转地址相应改为 `https://$host:8443$request_uri`。域名和 IP 同时访问时，须将两者加入 `ALLOWED_HOSTS`，并满足相应证书要求。客户端不会携带认证跟随重定向，应填写最终 API 地址。

Apple 平台的 ATS 配置已允许用户自定义 HTTP（原生实机与发布审核仍待验收）；Android 已配置明文连接。服务器资源规划见仓库的 `docs/fly_2_server_capacity.md`。

## 数据、备份、升级

数据库使用 `pgdata` 卷。blob 使用 `blobs` 卷，在 API 内为 `/var/lib/fly/storage/<user UUID>/<SHA-256>`；本地存储适配器预留独立 BlobStorage 接口。

```bash
cd /opt/fly/server
chmod +x deploy/backup.sh
./deploy/backup.sh /opt/fly-backups
```

脚本暂停 API 写入，将 PostgreSQL 自定义格式 dump 和 blob 压缩包一起备份，然后恢复 API。HTTP 部署的管理命令选择 `-f docker-compose.http.yml`；备份脚本通过 `COMPOSE_FILE=docker-compose.http.yml ./deploy/backup.sh /opt/fly-backups` 选择同一套配置。备份属于敏感用户数据，应限制权限、加密离机保存、定期在独立环境演练恢复。

恢复到新的空环境，启动 postgres 后使用 `pg_restore`；blob 包在 API 停止时解压到同一个存储卷，并恢复 uid 10001 所有权。不要把数据库和 blob 从不同时间点的备份混用。

```bash
docker compose up -d postgres
docker compose exec -T postgres pg_restore -U fly -d fly --clean --if-exists < /path/fly.dump
# 在确认目标为新建恢复环境后，再导入对应 blob 备份。
docker compose run --rm --no-deps --user root --entrypoint sh api \
  -c 'tar -xzf - -C /var/lib/fly/storage && chown -R 10001:10001 /var/lib/fly/storage' < /path/fly-blobs.tar.gz
docker compose up -d api nginx
```

升级先备份，再更新代码并运行 `docker compose up -d --build api nginx`。API 启动执行 `alembic upgrade head`；迁移失败则不启动 HTTP 服务。不要删除数据卷。旧客户端不可直接打开已经迁移到版本 18 的本地数据库；回退 1.0 必须使用升级前的本地备份。

## 本地开发与测试

### 2.0.1 文件策略（历史，已被当前规则替代）

当前 2.0.7 的云配置固定 `CLOUD_FILE_TRANSFER_ENABLED=false`，对所有邮箱、所有用户都禁止实体文件接口。原白名单配置仅用于旧协议兼容测试，不再是当前云产品能力。设备码、三设备测试和现有官网接入见 [部署说明](deploy/cloud_sync_20261101.md)。
