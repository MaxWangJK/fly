# Ubuntu 简单部署：PostgreSQL + Python

2026-11-09。这是当前推荐方式，不需要 Docker，也不改变现有 PHP 官网。按 Ubuntu 24.04（系统 Python 3.12）编写；后台是普通 Python 服务，PostgreSQL 单独安装。部署由你在服务器执行，开发电脑没有操作真实 Ubuntu。新增匿名统计、管理页和安装包更新检测请同时阅读 [本轮升级步骤](analytics-updates.md)。

最终结构：**现有 Nginx → `127.0.0.1:18766` Python 服务 → 本机 PostgreSQL**。客户端“我的”中自建地址留空即使用系统默认服务，无需填写官网域名；部署接口仍为 `world-workshop.cn/api`。支持邮箱注册、登录、找回密码和注销；只同步业务数据，不同步文件或图片内容。

## 1. 安装数据库，上传代码

Ubuntu 执行：

```bash
sudo apt update
sudo apt install -y postgresql python3-venv python3-pip curl
sudo systemctl enable --now postgresql
sudo -u postgres createuser --pwprompt fly
sudo -u postgres createdb --owner=fly fly
sudo mkdir -p /opt/fly-sync
```

`createuser` 会要求输入并确认数据库用户 `fly` 的密码，输入时不显示；记住它，第 2 步还要填写。已有可用的用户/数据库就保留，不重复创建。不要将数据库的 5432 端口开放给公网。

推荐上传本次 `Fly-Sync-2.0.21-build57-ubuntu-native-20261109.tar.gz` 原生后台包，在服务器执行：

```bash
sudo tar -xzf /tmp/Fly-Sync-2.0.21-build57-ubuntu-native-20261109.tar.gz -C /opt/fly-sync
```

上例假设把压缩包上传到了 `/tmp`。也可手动上传最新后台源码到 `/opt/fly-sync/server`，但不上传 Windows `.venv`、缓存和测试数据库。目录应有 `app/`、`alembic/`、`requirements.lock`、`alembic.ini` 和 `deploy/`。旧 build43 后台包不包含找回/注销和本部署配置。若是更新已有后台，先按下方“日常更新与备份”停止服务和备份，再解压覆盖公开代码。

另把开发电脑 `server/private/smtp.json` 安全上传到 `/opt/fly-sync/server/private/smtp.json`。真实发件配置没有放入公开后台包或 Git，不要上传到官网公开目录。保留你已有的发件配置即可，不需要重新填写授权码。

## 2. 一条命令安装 Python 服务

```bash
cd /opt/fly-sync/server
sudo bash deploy/install-native.sh
```

脚本会创建独立运行用户、虚拟环境、安装 Python 依赖、生成配置并开启服务和开机自启。第一次只问刚才数据库用户 `fly` 的密码，自动生成 `.env` 和稳定的 JWT 密钥，特殊字符会正确编码，密码不会出现在命令或输出中。重复运行保留已有 `.env` 和数据库，已有运行用户也不会重建。请在交互式 SSH 终端执行。

已有其他数据库名称/用户：保留原配置，或在 `.env` 中将 `DATABASE_URL` 改为原来的 PostgreSQL 连接。数据库在另一台机器可给初始化工具加 `--db-host 数据库内网地址 --db-port 5432`；需另外保证两台机器间数据库访问和连接加密，本文默认同一主机的回环连接。

启动结果与日志

```bash
sudo systemctl status fly-sync --no-pager
curl --fail http://127.0.0.1:18766/api/health
```

启动时会自动执行数据库增量迁移到 `0005`，不需要手动创建业务表。Python 使用独立系统用户运行，开机自启，异常退出后自动重启，日志由系统保存；统计路由访问日志被过滤。

健康接口应返回 `status: ok`，能力包含 `emailRegistration: true`、`passwordReset: true`、`deleteAccount: true`、`fileContents: false`。检查迁移或查看错误：

```bash
sudo -u fly-sync .venv/bin/alembic current
sudo journalctl -u fly-sync -n 80 --no-pager
```

常见问题：密码认证失败时核对 `.env` 与数据库用户密码；邮件失败时核对私有文件权限和服务器出站 TCP 465；18766 已占用时先核对旧同步进程，不同时启动两份服务。

## 3. Nginx 接入现有网站

已经按之前文档配置了 `/api/` 转发到 `127.0.0.1:18766`，保留该规则并补入 [本轮升级步骤](analytics-updates.md) 中更精确的 `/api/stats/` 日志关闭块。还没有添加时，将 [nginx-existing-site.locations.conf](nginx-existing-site.locations.conf) 中的 location 内容放进你现有域名的 HTTPS `server` 块内，然后执行：

```bash
sudo nginx -t
sudo systemctl reload nginx
curl --fail https://world-workshop.cn/api/health
```

继续使用原 PHP 根目录、证书和 PHP-FPM。保留官网 `/api/checkout`、`/api/activate` 的 PHP 路由；其余 `/api/` 和 `/api/ws` 交给 Python。不替换整个现有网站配置，也不要重复添加同名 location。完整参考配置见 [world-workshop.nginx.conf](world-workshop.nginx.conf)。

至此可在手机和电脑选择云同步，点击开启后在“我的”使用相同邮箱注册/登录测试；默认服务不用填地址，自建服务在“我的”填写。真实邮件投递、三设备及注销流程用隔离测试账号验收，不使用真实工作账号做删除试验。

## 日常更新与备份

更新只需要停止服务、备份数据库、上传新公开代码、安装依赖并重启；**保留 `.env`、`private/`、`.venv/` 和数据库**。

```bash
sudo systemctl stop fly-sync
sudo sh -c 'umask 077; sudo -u postgres pg_dump -Fc fly > /opt/fly-sync/fly-before-update.dump'
```

确认备份命令成功后上传新代码，然后：

```bash
cd /opt/fly-sync/server
sudo bash deploy/install-native.sh
```

`.env` 和 `private/smtp.json` 另作私有备份；当前云模式没有文件内容，但曾启用旧云文件上传的实例还需备份 `/var/lib/fly/storage`。不要以重建数据库或删除数据目录的方式更新。

如果服务器连 Python 软件源也无法下载，需要在另一台相同 Ubuntu/Python/CPU 架构的机器下载依赖后上传；无需重新引入 Docker：

```bash
# 可联网的同环境 Linux 机器
python3 -m pip download --only-binary=:all: -r requirements.lock -d wheels
# 上传 wheels/ 后，在服务器替代联网 pip install
sudo -u fly-sync .venv/bin/python -m pip install --no-index --find-links wheels -r requirements.lock
```

参考：[PostgreSQL Ubuntu 安装](https://www.postgresql.org/download/linux/ubuntu/)、[systemd 服务](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)、[Uvicorn 部署](https://www.uvicorn.org/deployment/)。以上配置和文档会随源码转移；Ubuntu 实机验收尚未执行。
