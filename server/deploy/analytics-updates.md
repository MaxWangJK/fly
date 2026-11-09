# Ubuntu：新增匿名统计与更新服务

2026-11-09，后台迁移 `0005`。继续使用现有 PostgreSQL、Python、Nginx 和 PHP 官网，不需要 Docker、不增加监听端口。本文由你在 Ubuntu 执行；开发电脑未连接生产服务器。

## 已有服务升级

先将 `Fly-Sync-2.0.21-build57-ubuntu-native-20261109.tar.gz` 上传到服务器 `/tmp`。已有 `.env`、JWT、数据库和 `private/smtp.json` 必须保留，不运行初始化建库命令。先停止并备份：

```bash
sudo systemctl stop fly-sync
sudo sh -c 'umask 077; sudo -u postgres pg_dump -Fc fly > /opt/fly-sync/fly-before-0005.dump'
sudo cp -a /opt/fly-sync/server/.env /opt/fly-sync/server/.env.before-0005
sudo tar -xzf /tmp/Fly-Sync-2.0.21-build57-ubuntu-native-20261109.tar.gz -C /opt/fly-sync
cd /opt/fly-sync/server
sudo nano .env
```

确认备份成功后才覆盖代码。保留原配置，增加下列三项；管理员密码用密码管理器生成至少 16 位随机值，只存服务器 `.env`。不要在公开仓库或聊天填写真实密码。

```dotenv
ANALYTICS_ADMIN_USERNAME=admin
ANALYTICS_ADMIN_PASSWORD=替换为至少16位随机密码
RELEASE_DIRECTORY=/var/www/fly/public/downloads
```

如果 `.env` 中密码含空格、`#` 等字符，用双引号并按 dotenv 规则转义；推荐使用 URL 安全随机字符。首次部署请先完成 [原生部署步骤](ubuntu-native.md)，包括上传私有邮件配置；已有服务无需重新生成。

```bash
sudo mkdir -p /var/www/fly/public/downloads
sudo bash deploy/install-native.sh
sudo -u fly-sync .venv/bin/alembic current
sudo systemctl status fly-sync --no-pager
curl --fail http://127.0.0.1:18766/api/health
```

服务启动前自动执行 `alembic upgrade head`，`current` 应为 `0005`。也可显式执行 `sudo -u fly-sync .venv/bin/alembic upgrade head`。安装脚本保留现有 `.env`，不会自动给旧文件追加新设置。服务用户需要下载目录及其父目录的读取/遍历权限，保持公开安装包常规 0644、目录 0755 即可；不要修改整个网站的所有权，不把邮件或其他私密文件放进下载目录。

## Nginx 与官网共存

在现有 HTTPS `server` 内，保留 PHP 的 `location /`、`location = /index.php`、原证书和根目录。使用同目录 [nginx-existing-site.locations.conf](nginx-existing-site.locations.conf) 的 API location；已有配置时只补统计块，避免重复同名 location：

```nginx
location ^~ /api/stats/ {
    access_log off;
    error_log /dev/null crit;
    client_max_body_size 1k;
    proxy_pass http://127.0.0.1:18766;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP "";
    proxy_set_header X-Forwarded-For "";
    proxy_set_header Forwarded "";
    proxy_set_header Authorization "";
    proxy_set_header Cookie "";
    proxy_read_timeout 5s;
    proxy_send_timeout 5s;
}
```

`proxy_pass` 后没有 `/`，保留 `/api/stats/...` 原路径。原有通用 `/api/` 转发已涵盖 `/api/admin/stats` 和 `/api/updates/`；管理认证需要保留 Authorization，**不要把统计块的清空规则复制进通用 API 块**。`/api/checkout`、`/api/activate` 继续由既有 PHP 路由处理。WebSocket 配置不变。

```bash
sudo nginx -t
sudo systemctl reload nginx
curl --fail https://world-workshop.cn/api/health
```

统计块关闭访问和错误记录，应用还会过滤 Uvicorn 的统计 access log。外层代理、监控、CDN 或系统审计如有请求日志，需要另行排除此路径。生产 API 仍只监听回环地址，PostgreSQL 不对公网开放。

## 接口验收

先在测试环境执行；若直接用正式域名，下面的随机安装会计入真实统计，不能把它当作“无痕健康检查”。不要用真实用户业务信息替代编号。

```bash
CODE=$(python3 -c 'import secrets; print(secrets.token_hex(8))')
curl --fail -X POST "https://world-workshop.cn/api/stats/$CODE/1"
curl --fail -X POST "https://world-workshop.cn/api/stats/$CODE/2"
curl --fail -X POST "https://world-workshop.cn/api/stats/$CODE/2"
curl --fail --user admin https://world-workshop.cn/api/admin/stats/overview
```

curl 提示时输入管理员密码，避免密码写入命令历史。前三次都应为 200 空正文，相同编号只增加一个安装、一个当日活跃；管理 API 返回聚合数字。浏览器打开 `https://world-workshop.cn/api/admin/stats`，输入相同管理员凭据。无凭据应 401；未设管理员密码应 404。页面只有指标和两幅趋势图。

更新包测试：先在服务器准备真实安装包上传目录。以未来发布的 `Fly-2.1.exe` 为例：

```bash
# 先把安装包上传到 /var/www/fly/public/downloads/Fly-2.1.exe.part
sudo mv /var/www/fly/public/downloads/Fly-2.1.exe.part /var/www/fly/public/downloads/Fly-2.1.exe
curl --fail https://world-workshop.cn/api/updates/latest/windows
curl --fail https://world-workshop.cn/api/updates/latest/android
```

API 自动选同平台最高数字版本。Android 同理使用 `.apk.part` 再改名 `.apk`，且必须是原发布签名。命名、测试包排除和下载逻辑见 [更新说明](../../docs/app_updates.md)。没有重启要求。下载到浏览器后由用户和操作系统安装，不能改个高版本文件名就把旧二进制当作新版本。

Windows 新安装/干净测试配置首次运行：安装 +1、活跃 +1；同日重开不增加；次日重开只增加当天活跃。使用隔离用户或新系统配置，不删除真实 Fly 配置来制造测试环境。离线和统计故障时，主界面应正常使用且无错误提示。旧客户端没有更新检测功能，需先手动安装本轮版本，之后才能接收更新提示。

## 可选 Compose

服务器不能使用 Docker 时跳过本节。已有容器用户保留数据卷、JWT 和邮件文件，设置 `.env` 中管理员账号，并将官网目录映射为只读发布目录：

```dotenv
FLY_RELEASES_DIR=/var/www/fly/public/downloads
ANALYTICS_ADMIN_USERNAME=admin
ANALYTICS_ADMIN_PASSWORD=替换为至少16位随机密码
```

Compose 在容器内设置 `RELEASE_DIRECTORY=/var/lib/fly/releases`；主机路径由 `FLY_RELEASES_DIR` 指定，不受原生变量影响。先建好目录，再执行原先相同的 compose 组合。独立容器示例：

```bash
docker compose up -d --build postgres api
docker compose exec api alembic current
docker compose up -d nginx
```

已有官网使用 `docker-compose.cloud.yml` 的用户改用下面两条命令，不启动独立 nginx 占用网站端口：

```bash
docker compose -f docker-compose.cloud.yml up -d --build postgres api
docker compose -f docker-compose.cloud.yml exec api alembic current
```

不要 `down -v`。Dockerfile 的 `COPY app` 包含后台 HTML，迁移随启动执行。当前开发机没有 Docker CLI，因此**未验证 Docker build/up**；Ubuntu/systemd、真实 PostgreSQL 和 Nginx 实机同样需要你部署验收。

## 排错与回滚

管理页 404：检查 `.env` 新密码是否实际加载并重启；401：检查独立管理员凭据而非 Fly 登录账号。更新为空：检查路径、权限、文件非零、命名符合规则；更新 503：检查读取权限和是否仍在覆盖传输。统计 503：检查数据库迁移和服务健康，应用不会打印随机编号或请求正文。

```bash
sudo journalctl -u fly-sync -n 80 --no-pager
sudo -u fly-sync .venv/bin/alembic current
```

回滚应用代码可先停服务、恢复上一版公开代码并保留原 `.env`/私有目录，再启动；旧后台可以忽略新统计表。不要在已有统计数据时随意 downgrade，`0005 → 0004` 会删除两张统计表。恢复数据库前先确认备份和停机安排，不以清库处理迁移问题。
