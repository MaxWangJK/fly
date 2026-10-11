# Fly 2.0 Sync Backend

后端目录：`E:\workSpace\fly\server`。Ubuntu 建议放在 `/opt/fly/server`。

Python 3.12 容器、FastAPI、SQLAlchemy 2、PostgreSQL 16、Alembic；Redis 不参与核心协议。
SQLite 仅用于隔离测试，不替代生产 PostgreSQL。

## 协议与存储

- `/api/auth/register|login|refresh|logout`：邮箱 trim/lowercase、Argon2id、20 分钟 JWT、30 天设备独立 refresh token。数据库仅保存 refresh token 的 SHA-256；令牌轮换，设备撤销立即拒绝后续请求。
- `/api/account/me`、`/api/devices`、`/api/devices/{id}/revoke`：全部按认证用户隔离。
- `POST /api/sync/push`：最多 200 条。`mutationId` 幂等，重复 ID 的不同内容返回 409。整个批次提交或回滚。
- `GET /api/sync/pull?after=0&limit=100`：变更日志游标，最多 200 条、约 4 MiB/页。每条记录最多 1 MiB。
- `/api/sync/bootstrap`：采用同样的持久变更日志分页，客户端折叠记录历史。当前实现没有快照压缩，首次同步会读取历史变更。
- `/api/sync/conflicts`、`POST /api/sync/conflicts/{id}/resolve`：保存候选数据，选择另一版本需先发送基于当前版本的 mutation，然后标记处理完成。
- `/api/files/upload/init`、`PUT /api/files/upload/{id}/chunk?offset=...`、`POST /api/files/upload/{id}/complete`：4 MiB 分片、7 天可恢复会话、SHA-256、单文件 2 GiB 上限。用户内去重，临时文件 `.part` 校验后原子重命名。
- `/api/files/{fileId}/download`：通过受保护的文件元数据获取 blob，文件名不参与服务器路径构建。
- `/api/ws`：接受后第一帧传 JWT，随后只发 `sync_available/latest_cursor`。不在 URL 中传 token。每 2 秒检查持久日志，断线后仍以 HTTP 游标拉取为准。
- `/api/health`：数据库连接检查，只返回状态及 API 版本。

服务端使用 users 行锁串行化同一用户的 push，包含首次记录创建。全局 seq 的用户子序列按提交顺序可见，避免并发事务的游标跳过。记录版本独立于客户端本地业务 version 和设备时钟。
不同业务字段自动合并；`updated_at` 和本地 `version` 不参与冲突判断。同字段以成功提交顺序产生当前值，并保存两份候选。删除优先；恢复必须显式使用当前墓碑版本。附件二进制并发保留原 canonical 并创建冲突文件副本；笔记块并发保留另一块副本。

表：users、devices、refresh_tokens、sync_records、sync_changes、processed_mutations、sync_conflicts、file_blobs、file_upload_sessions。JSON 在 PostgreSQL 使用 JSONB。
`app/schema_v1.py` 是迁移 0001 的冻结定义；以后变更新增 Alembic revision，不修改冻结定义。

## Ubuntu 22.04 / 24.04 部署

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

`deploy/nginx.conf` 提供完整域名示例，HTTP 跳转 HTTPS，认证端点共享 IP 限流，WebSocket 转发，8 MiB 请求上限。

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

## 数据、备份、升级

数据库使用 `pgdata` 卷。blob 使用 `blobs` 卷，在 API 内为 `/var/lib/fly/storage/<user UUID>/<SHA-256>`；本地存储适配器预留独立 BlobStorage 接口。

```bash
cd /opt/fly/server
chmod +x deploy/backup.sh
./deploy/backup.sh /opt/fly-backups
```

脚本暂停 API 写入，将 PostgreSQL 自定义格式 dump 和 blob 压缩包一起备份，然后恢复 API。备份属于敏感用户数据，应限制权限、加密离机保存、定期在独立环境演练恢复。

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

```bash
cd /opt/fly/server
python3.12 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
export APP_ENV=development
export JWT_PRIVATE_SECRET=$(openssl rand -hex 32)
export DATABASE_URL='postgresql+psycopg://fly:YOUR_PASSWORD@127.0.0.1/fly'
export STORAGE_ROOT="$PWD/storage"
alembic upgrade head
uvicorn app.asgi:app --host 127.0.0.1 --port 8000
pytest -q
```

自动测试覆盖账户归一化、令牌轮换/撤销、用户隔离、幂等、字段合并、候选冲突、删除/恢复、原子批次、游标分页、上传恢复/去重/校验、路径注入及请求大小/认证限流。测试使用临时 SQLite 和临时存储，无生产网络调用。

Flutter 两客户端端到端测试使用独立临时服务（测试后按 Ctrl+C 停止）。在后端目录启动：

```bash
.venv/bin/python -m tests.run_test_server
```

另开终端，在 Flutter 仓库根目录运行：

```bash
FLY_SYNC_TEST_URL=http://127.0.0.1:18765/api flutter test test/sync_two_client_test.dart
```

Windows PowerShell 使用以下命令，分别在两个终端执行：

```powershell
# 终端 1
cd E:\workSpace\fly\server
& '.venv\Scripts\python.exe' -m tests.run_test_server
```

```powershell
# 终端 2
cd E:\workSpace\fly
$env:FLY_SYNC_TEST_URL='http://127.0.0.1:18765/api'
flutter test test/sync_two_client_test.dart
```

该临时入口仅绑定 loopback，不用于生产部署。未设置测试地址时，此测试显式跳过。

本阶段没有邮箱验证、忘记密码重置、账户删除 UI、计费系统或大型管理员页面。`/account/me` 显式返回能力标志；不会通过邮箱直接重置密码。
