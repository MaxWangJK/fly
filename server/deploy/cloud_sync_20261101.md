# Ubuntu 部署：保留 PHP 官网，增加 Fly 云同步

2026-11-01，源码 2.0.7+43，后台迁移 `0003`。由所有者自行部署；开发电脑没有操作真实服务器。本指南按你提供的 Nginx、PHP 路径及现有证书编写，适用于已有官网的 Ubuntu 主机。

## 1. 部署后的地址

| 地址或端口 | 处理方 |
| --- | --- |
| `https://world-workshop.cn/` 及官网页面 | 原 Nginx → 原 PHP-FPM |
| `/api/checkout`、`/api/activate` | 原官网 PHP 接口，单独保留 |
| `https://world-workshop.cn/api/health` | 新 FastAPI 同步服务 |
| `https://world-workshop.cn/api/auth/...`、`/api/sync/...` | 新邮箱账号及数据同步 |
| `wss://world-workshop.cn/api/ws` | 新 WebSocket 变更提醒 |
| `127.0.0.1:18766` | 同步容器只绑定本机，公网通过已有 Nginx 进入 |
| PostgreSQL | 仅容器网络访问，不映射公网端口 |

不需要新域名或新证书，也不把同步 Python 代码放进 `/var/www/fly/public`。官网与同步数据库、用户登录暂未统一。云端只传业务记录及文件信息，不传图片或文件字节。默认本地同步，用户登录并选择云同步后才启用。

完整可参考配置：[world-workshop.nginx.conf](world-workshop.nginx.conf)。只添加路由时使用 [nginx-existing-site.locations.conf](nginx-existing-site.locations.conf)。**不要遗漏官网原有两个 `/api/` 接口，也不要在同一 server 块重复添加相同 location。**

## 2. 准备服务器

先确认系统和已有服务：

```sh
lsb_release -a
sudo nginx -t
systemctl status nginx --no-pager
docker --version
docker compose version
sudo ss -lntp
```

已有正常 Docker/Compose 则保留，跳到下一节。没有 Docker 时按 [Docker 官方 Ubuntu 安装说明](https://docs.docker.com/engine/install/ubuntu/) 安装。新主机的官方仓库步骤如下；若已有其他 Docker/containerd 安装，应先按官方说明核对兼容，别直接卸载正在承载业务的运行环境。

```sh
sudo apt update
sudo apt install -y ca-certificates curl python3
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker compose version
```

保留原 Nginx/PHP-FPM，不运行旧独立站点 `install.sh`，不启动基础 Compose 中的另一个 Nginx。本文所有容器命令都指定 `-f docker-compose.cloud.yml`。

## 3. 上传后台包与私有发件配置

本轮交付包为 `dist/Fly-Sync-2.0.7-build43-ubuntu-20261101.tar.gz`，包含后台公开源码、固定依赖、迁移、Compose 与本指南，**不包含真实 SMTP、`.env`、数据库或业务文件**。包内 `server/SOURCE.json` 记录源码提交。公开 Git 不会带走被忽略的发件配置；仅下载旧远端源码也不能代替本轮交付包。

在 Windows PowerShell 上传（将 `ubuntu@SERVER_IP`、端口改成你的连接信息；也可用 SFTP）：

```powershell
scp -P 22 E:/workSpace/fly/dist/Fly-Sync-2.0.7-build43-ubuntu-20261101.tar.gz ubuntu@SERVER_IP:/tmp/
scp -P 22 E:/workSpace/fly/server/private/smtp.json ubuntu@SERVER_IP:~/fly-smtp.json
```

首次部署在 Ubuntu 解压：

```sh
sudo install -d -m 0755 /opt/fly-sync
sudo tar -xzf /tmp/Fly-Sync-2.0.7-build43-ubuntu-20261101.tar.gz -C /opt/fly-sync
cd /opt/fly-sync/server
chmod 0600 "$HOME/fly-smtp.json"
sudo install -d -m 0700 -o 10001 -g 10001 private
sudo install -m 0600 -o 10001 -g 10001 "$HOME/fly-smtp.json" private/smtp.json
```

容器用户 UID/GID 为 10001。私有配置只读挂载到 `/run/fly/private/smtp.json`，不进入镜像、公开仓库或客户端。已有真实发件参数在开发电脑该文件中，不需要重新抄授权码到文档。模板是 [mail-settings.example.json](mail-settings.example.json)。

## 4. 创建生产配置并启动

仅首次部署运行：

```sh
cd /opt/fly-sync/server
sudo python3 deploy/prepare_cloud.py
sudo docker compose -f docker-compose.cloud.yml config --quiet
sudo docker compose -f docker-compose.cloud.yml up -d --build --wait --wait-timeout 180
sudo docker compose -f docker-compose.cloud.yml ps
sudo docker compose -f docker-compose.cloud.yml exec api alembic current
curl --fail http://127.0.0.1:18766/api/health
```

初始化工具生成不回显的随机数据库密码与 JWT 密钥，数据库连接密码自动匹配，`.env` 以所有者读写权限创建；若文件已存在，拒绝覆盖。`.env` 中固定项目名 `fly-sync`，避免换路径就误建另一套卷。已有同步部署应继续使用**原 `.env`、项目名、卷和密钥**，不要套用新项目名或重跑初始化替换旧身份。

关键值应为：`ALLOW_PASSWORD_AUTH=true`、`CLOUD_FILE_TRANSFER_ENABLED=false`、`APP_ENV=production`，允许主机为 `world-workshop.cn,localhost,127.0.0.1`。Compose 再次固定开启邮箱、关闭云文件内容。启动先执行 Alembic 增量升级；`0003` 新增邮箱验证和限流，不删除旧用户/业务记录。

`alembic current` 应包含 `0003`；健康响应形状如下，时间会不同：

```json
{
  "status": "ok",
  "apiVersion": 1,
  "serverTime": "...",
  "capabilities": {
    "automaticMerge": true,
    "deviceEnrollment": true,
    "fileContents": false,
    "emailRegistration": true
  }
}
```

查看启动失败原因：

```sh
sudo docker compose -f docker-compose.cloud.yml logs --tail=100 api postgres
```

后台包固定 Python 依赖；PostgreSQL 使用 16 系列，数据库和旧项目卷不能随意删除。后续更新继续复用这份 `.env`，JWT 密钥不能每次重建，否则旧会话及验证摘要失效。

## 5. 修改你现有的 Nginx

先找当前实际启用的站点文件，不要猜路径，也不新增重复域名的第二个 server：

```sh
ls -l /etc/nginx/sites-enabled
sudo nginx -T 2>/dev/null | less
```

找到包含 `server_name world-workshop.cn` 的配置文件。以下 `FLY_SITE` 是常见示例，先替换成实际路径；备份放在 sites-enabled 之外：

```sh
FLY_SITE=/etc/nginx/sites-available/fly
sudo test -f "$FLY_SITE"
sudo install -d -m 0700 /root/fly-nginx-backups
sudo cp -a "$FLY_SITE" "/root/fly-nginx-backups/fly-before-sync-$(date +%Y%m%d-%H%M%S).conf"
sudo nano "$FLY_SITE"
```

推荐只把 [路由片段](nginx-existing-site.locations.conf) 放进现有 **443 HTTPS server 块**，与原 `location /`、PHP 配置同级。原证书路径、根目录 `/var/www/fly/public`、PHP socket `/run/php/fly.sock` 继续保留。原 80 跳转保持不变。若希望对照整份配置，打开 [完整示例](world-workshop.nginx.conf)，它已保留你提供的这些路径。

路由片段中特别注意：

- `/api/checkout`、`/api/activate` 精确匹配后内部转到原 `/index.php`，POST 方法、正文和原请求 URI 保留，官网逻辑继续处理。
- `/api/ws` 精确匹配，转发 Upgrade/Connection 并关闭代理缓冲。
- 其余 `location ^~ /api/` 转发至 `http://127.0.0.1:18766`。`proxy_pass` **末尾没有 `/`**，因此保留 `/api/` 前缀；FastAPI 的路由也包含这个前缀。
- 读取超时 90 秒大于后台约 30 秒心跳；普通 HTTP 请求不强制 Upgrade。

上述 Upgrade 设置依据 [Nginx 官方 WebSocket 说明](https://nginx.org/en/docs/http/websocket.html)。原 `listen 443 ssl http2` 沿用你的配置；如果新版 Nginx 提示弃用，可按本机版本改为 `listen 443 ssl;` 与 `http2 on;`，不影响路由设计。

保存后，只有语法通过才重新加载：

```sh
sudo nginx -t
# 上一步必须成功后再执行：
sudo systemctl reload nginx
curl --fail https://world-workshop.cn/api/health
curl -I https://world-workshop.cn/
```

未登录的路由检查可使用以下只读 GET，请求不会购买或激活：

```sh
curl -i https://world-workshop.cn/api/checkout
curl -i https://world-workshop.cn/api/activate
```

这两个地址 GET 目前应得到官网的 HTML 404 页面，而不是 FastAPI 的 JSON `Not Found`；其真实业务方法是 POST。再从浏览器检查官网首页、登录页和下载页。不要随意开启数据库或 18766 的公网端口。

## 6. 手机、电脑及邮件验收

1. 安装本轮 build43；原测试签名安装选测试 APK，原正式签名安装选正式 APK。云端测试前保留完整业务备份；新 schema20 不用旧 build42 打开。
2. 设置 → 同步，选择云同步；地址填 `world-workshop.cn/api` 即可。测试连接成功，默认 HTTPS。
3. 用自己的邮箱注册：图形验证 → 六位邮箱码 → 设置和确认密码。真实邮件投递在这一步验收；本地自动测试没有发送实际邮件。
4. 另一台设备用同一邮箱密码登录，确认同步空间相同。三台设备同一账号，不要分别注册成三个账号。
5. 工作电脑新建客户/任务，前台手机和家庭电脑应在收到提醒后获取；手机创建、修改后也立即上传。
6. 手机切后台，在另一端新增；手机回到前台后应立即拉取。后台期间本轮不承诺收到系统推送或每五分钟唤醒。
7. 两台电脑分别离线创建不同客户或任务，恢复后应取并集；同一客户不同字段修改应保留双方，同字段按现有自动规则合并，不弹人工冲突。
8. 云同步不上传图片或文件字节。文件信息出现不表示文件已可打开，需要实体内容时用本地配对同步。

原临时空间已含数据的，先使用原会话或一次性测试码进入，再在云设置绑定邮箱，保留原用户 ID。不要先建一个新账号再期待两个空间自动混合。测试码 CLI 仍可用：

```sh
sudo docker compose -f docker-compose.cloud.yml exec api python -m app.cli create-sync-user
sudo docker compose -f docker-compose.cloud.yml exec api python -m app.cli issue-device-code --user-id USER_UUID --output /tmp/fly-device.code
```

已有用户只执行第二条，`USER_UUID` 替换成原空间 ID；每设备一个码，默认 15 分钟有效，单次使用。代码是接入凭据，使用后由管理员移除临时文件。

## 7. 备份、更新与恢复

更新前在当前项目的 server 目录备份 PostgreSQL，并安全保管 `.env` 与 `private/smtp.json`：

```sh
cd /opt/fly-sync/server
set -o pipefail
sudo install -d -m 0700 /root/fly-sync-backups
FLY_BACKUP=/root/fly-sync-backups/fly-$(date +%Y%m%d-%H%M%S).dump
sudo docker compose -f docker-compose.cloud.yml exec -T postgres pg_dump -U fly -d fly -Fc | sudo tee "$FLY_BACKUP" >/dev/null
sudo chmod 0600 "$FLY_BACKUP"
sudo cat "$FLY_BACKUP" | sudo docker compose -f docker-compose.cloud.yml exec -T postgres pg_restore --list > /tmp/fly-backup-contents.txt
test -s /tmp/fly-backup-contents.txt
```

上述命令以 Bash 执行；转储与列表校验都成功后再更新。更新仅替换公开源码与镜像，保留 `.env`、private、固定 Compose 项目名及卷，再执行原 `up -d --build --wait`。不要执行 `down -v`、清空卷或以 `create_all` 替代增量迁移。回退 API 镜像时先确认数据库兼容；涉及数据库恢复应停 API，并先在隔离库验证恢复，不能直接把线上卷覆盖掉。

后台不包含业务文件字节，数据库转储是云端业务数据的主要备份；本地电脑中的实体文件仍按应用完整备份另行保管。应把服务器备份复制到另一处安全位置，同机副本不等于独立备份。

## 8. 常见问题

| 现象 | 先检查 |
| --- | --- |
| `/api/health` 返回官网 HTML | Nginx 的 `/api/` 路由是否放在正确的 443 块、是否 reload |
| 502 | `127.0.0.1:18766` 是否健康、容器日志、端口是否被其他程序占用 |
| FastAPI 路由全部 404 | `proxy_pass` 是否多了尾部 `/`，导致删去 `/api/` 前缀 |
| 官网购买/授权入口失效 | 是否漏掉两个 PHP 精确匹配 location |
| 只在每五分钟更新 | WebSocket 的 101 升级、Upgrade 头、90 秒超时及客户端网络 |
| 邮件接口 503 | 私有文件读取权限、服务器出站 TCP465、邮箱服务授权及配置；查看日志，不公开发件凭据 |
| 429 | 触发 IP/邮箱发送与尝试限制，等冷却后再操作，不反复换图绕过 |
| 401 或登录后无法同步 | 原 JWT 密钥是否被换、会话过期/被撤销、是否登录了其他账号 |
| 更新后似乎没有旧数据 | Compose 项目名、`.env` 与原卷是否一致，先查原卷，不初始化替代数据库 |

同步调度、API 字段与后台推送计划见 [协议说明](../../docs/architecture/cloud_sync_runtime_20261101.md)。本机用官方便携 Nginx 1.30.6，对完整配置仅替换测试证书、路径和回环端口后，语法与 8 项路由/TLS/WebSocket 检查通过，包含原 PHP 接口 POST 方法、正文、URI 保留。PHP/API 均为隔离替身，没有执行真实官网业务。目标 Ubuntu 的 Docker/PostgreSQL、原 PHP、`docker compose config`、`nginx -t`、真实邮件及公网多设备验收仍在部署时执行。
