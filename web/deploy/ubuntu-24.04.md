# Fly 官网部署手册：Ubuntu Server 24.04 LTS

本手册适用于当前仓库的 `web/` 网站。部署后可以公开展示产品页面；账户登录和支付适配器尚未接入，方案价格尚未确定，因此保持购买关闭。以下正文使用 Apache、PHP 和 SQLite。如果服务器已经运行 Nginx 并占用 80/443 端口，请改用 [Nginx 部署步骤](ubuntu-24.04-nginx.md)，不要同时启动两个 Web 服务。

> 如果云服务器控制台显示的是“Ubuntu 24.04”，它就是本手册对应的版本。下文的 `fly.example.com`、`SERVER_IP`、`SSH_USER` 都要替换成自己的真实值。以下命令分为 **Windows PowerShell** 和 **Ubuntu SSH** 两种环境，不要混用。

## 1. 上线前准备

- 一台可通过 SSH 登录的 Ubuntu Server 24.04 LTS 云服务器，知道公网 IP、SSH 用户名及登录方式，该用户具有 `sudo` 权限。
- 一个域名，例如 `fly.example.com`。在域名服务商处给该域名添加指向服务器公网 IPv4 的 A 记录。如果添加 AAAA 记录，服务器必须同时具备可用的公网 IPv6。等待解析生效。
- 在云厂商的安全组或防火墙中放通入站 SSH 端口、TCP 80、TCP 443。SSH 端口以服务器实际配置为准，通常为 22。
- 在 Windows 上打开 PowerShell，进入项目目录 `E:\workSpace\fly`。

网站目录规划：

| 路径 | 用途 |
| --- | --- |
| `/var/www/fly/public` | Apache 唯一对外目录 |
| `/var/www/fly/src` | PHP 程序，不能直接对外访问 |
| `/var/www/fly/issuer_public_key.txt` | 桌面授权验签公钥 |
| `/var/lib/fly/fly.sqlite` | 订单和设备数据库 |
| `/etc/fly/apache-env.conf` | 网站配置 |
| `/etc/fly/*.pem` | 授权签发私钥与未来服务配置 |

**不要**把整个 `web/` 目录上传成网站根目录。日志、配置、授权签发私钥和 SQLite 数据都不能放到 `public/`。

## 2. 安装系统软件和配置防火墙（Ubuntu SSH）

先登录服务器：

```bash
ssh SSH_USER@SERVER_IP
```

安装系统包：

```bash
sudo apt update
sudo apt install -y apache2 libapache2-mod-php php-cli php-sqlite3 sqlite3 certbot python3-certbot-apache
sudo a2enmod rewrite
php -v
php -m | grep -Ei 'openssl|pdo_sqlite|sodium'
```

最后一条命令应能看到 `openssl`、`pdo_sqlite`、`sodium`。Ubuntu 24.04 的默认 PHP 为 8.3，满足本项目的 PHP 8.2+ 要求。

先确认当前 SSH 端口，**先放通 SSH 再启用 UFW**。默认 22 端口可执行：

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

如果 SSH 使用自定义端口，改用 `sudo ufw allow 实际端口/tcp`，确认规则存在后再执行 `sudo ufw enable`。云厂商安全组和 UFW 都必须放行，任意一处拦截都会导致无法访问。

## 3. 从 Windows 打包并上传网站

### 方法 A：用 Windows 图形界面压缩和上传

可以直接压缩整个 `web` 文件夹作为**传输文件**。目前仓库中的 `web` 包含 `public`、`src`、`deploy`、`tests`、`README.md` 和公钥，没有部署密钥。不过压缩前仍须检查 `web` 内没有 `config.php`、`.env`、`*.pem`、`*.sqlite`、日志或其他含密钥的文件；以后新增加的文件也要检查。整个压缩包只放在服务器登录用户的家目录，**不能直接解压到 Apache 网站根目录**。

1. 在 Windows 文件管理器中打开 `E:\workSpace\fly`，右键 `web` 文件夹，选择“压缩为 ZIP 文件”（或“发送到 → 压缩(zipped)文件夹”），得到 `web.zip`。
2. 使用能连接 SFTP 的图形工具，或云服务器控制台提供的文件上传功能，把 `web.zip` 上传到 SSH 用户的家目录，通常是 `/home/SSH_USER/web.zip`。SFTP 使用与 SSH 相同的地址、端口、用户名和密钥/密码。
3. SSH 登录 Ubuntu，检查 ZIP 内容、解压到家目录，再仅安装网站必需的三个项目：

   ```bash
   sudo apt install -y unzip
   unzip -l ~/web.zip
   mkdir -p ~/fly-upload
   unzip -q ~/web.zip -d ~/fly-upload
   ls ~/fly-upload/web
   sudo install -d -o root -g root -m 755 /var/www/fly
   sudo cp -a ~/fly-upload/web/public ~/fly-upload/web/src ~/fly-upload/web/issuer_public_key.txt /var/www/fly/
   sudo chown -R root:root /var/www/fly
   sudo find /var/www/fly -type d -exec chmod 755 {} +
   sudo find /var/www/fly -type f -exec chmod 644 {} +
   sudo test -f /var/www/fly/public/index.php
   sudo test -f /var/www/fly/src/Core.php
   ```

如果 `ls ~/fly-upload/web` 提示不存在，ZIP 可能没有包含最外层 `web` 文件夹：先执行 `ls ~/fly-upload`，若直接看到 `public`、`src` 和 `issuer_public_key.txt`，将上面 `sudo cp -a` 命令中的 `~/fly-upload/web/` 改为 `~/fly-upload/`。

### 方法 B：使用 PowerShell 命令行

若 Windows 已安装 `tar` 和 `scp`，可在 **Windows PowerShell** 中进入 `E:\workSpace\fly` 后执行：

```powershell
tar -czf "$env:TEMP\fly-web.tar.gz" -C web public src issuer_public_key.txt
tar -tzf "$env:TEMP\fly-web.tar.gz"
scp "$env:TEMP\fly-web.tar.gz" SSH_USER@SERVER_IP:~/fly-web.tar.gz
```

检查打包清单仅包含 `public/`、`src/`、`issuer_public_key.txt`。`SSH_USER@SERVER_IP` 是占位符，必须替换成真实登录信息。如果提示找不到 `tar` 或 `scp`，直接使用方法 A。如 SSH 使用自定义端口，上传命令添加 `-P 实际端口`；登录命令添加 `-p 实际端口`。

在 **Ubuntu SSH** 中安装网站文件：

```bash
sudo install -d -o root -g root -m 755 /var/www/fly
sudo tar -xzf ~/fly-web.tar.gz -C /var/www/fly
sudo chown -R root:root /var/www/fly
sudo find /var/www/fly -type d -exec chmod 755 {} +
sudo find /var/www/fly -type f -exec chmod 644 {} +
sudo test -f /var/www/fly/public/index.php
sudo test -f /var/www/fly/src/Core.php
```

两种方法任选一种。安装后，`/var/www/fly/public` 是唯一对外目录；程序代码由 root 持有，网页进程只读。保存 Windows 端本次打包文件，以便需要时回滚。

## 4. 创建数据目录和网站配置（Ubuntu SSH）

```bash
sudo install -d -o www-data -g www-data -m 700 /var/lib/fly
sudo install -d -o root -g www-data -m 750 /etc/fly
sudo nano /etc/fly/apache-env.conf
```

在编辑器中填入以下内容，先把域名换成实际域名。当前没有商户参数，价格保持 0，销售开关保持 0：

```apache
SetEnv FLY_BASE_URL https://fly.example.com
SetEnv FLY_DB_PATH /var/lib/fly/fly.sqlite
SetEnv FLY_PRICE_BASIC_CENTS 0
SetEnv FLY_PRICE_PRO_CENTS 0
SetEnv FLY_SALES_ENABLED 0
SetEnv FLY_ISSUER_PRIVATE_KEY_FILE /etc/fly/issuer.pem
```

保存后限制配置文件权限：

```bash
sudo chown root:root /etc/fly/apache-env.conf
sudo chmod 600 /etc/fly/apache-env.conf
```

初始化 SQLite 数据库并验证网页用户有写入权限：

```bash
sudo -u www-data env FLY_DB_PATH=/var/lib/fly/fly.sqlite php -r 'require "/var/www/fly/src/Core.php"; FlyWeb\Database::connect(); echo "database OK\n";'
sudo ls -l /var/lib/fly/fly.sqlite
```

应输出 `database OK`，数据库文件所有者应为 `www-data`。若失败，先检查 PHP 扩展和 `/var/lib/fly` 权限。

## 5. 配置 Apache（Ubuntu SSH）

```bash
sudo nano /etc/apache2/sites-available/fly.conf
```

粘贴下列配置并把 `fly.example.com` 换成实际域名：

```apache
<VirtualHost *:80>
    ServerName fly.example.com
    DocumentRoot /var/www/fly/public

    <Directory /var/www/fly/public>
        AllowOverride All
        Require all granted
    </Directory>

    IncludeOptional /etc/fly/apache-env.conf
    ErrorLog ${APACHE_LOG_DIR}/fly-error.log
    CustomLog ${APACHE_LOG_DIR}/fly-access.log combined
</VirtualHost>
```

启用网站：

```bash
sudo a2dissite 000-default.conf
sudo a2ensite fly.conf
sudo apache2ctl configtest
sudo systemctl enable --now apache2
sudo systemctl status apache2 --no-pager
```

首次部署应使用 `enable --now` 启动 Apache 并设置开机自启；`reload` 只能用于已在运行的服务。`configtest` 必须显示 `Syntax OK`，服务状态应显示 `active (running)`。如果启动失败，执行 `sudo journalctl -u apache2 -n 80 --no-pager` 查看错误；常见原因是配置错误或 80 端口已被其他程序占用。用浏览器先访问 `http://fly.example.com/`，应能看到 Fly 首页和产品截图。也可在服务器上检查：

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: fly.example.com' http://127.0.0.1/
```

如果首页正常但站内页面出现 404，请确认 `rewrite` 模块已启用、`public/.htaccess` 已上传，以及 Apache 配置中的 `AllowOverride All` 存在。

## 6. 申请 HTTPS 证书（Ubuntu SSH）

确认域名解析已经指向服务器、80/443 端口可从公网访问后执行：

```bash
sudo certbot --apache -d fly.example.com --redirect
sudo apache2ctl configtest
sudo systemctl reload apache2
sudo certbot renew --dry-run
```

Certbot 会申请证书、配置 Apache HTTPS 和 HTTP 到 HTTPS 的跳转。按提示填写收取证书通知的邮箱。`renew --dry-run` 应成功；系统安装的 Certbot 会负责后续续期，建议每月查看一次证书状态：

```bash
sudo certbot certificates
```

检查 Certbot 生成的 `:443` 虚拟主机仍使用 `/var/www/fly/public`，并包含 `IncludeOptional /etc/fly/apache-env.conf`。如果没有这行，把它加到 HTTPS 虚拟主机内部，再运行 `sudo apache2ctl configtest` 和 `sudo systemctl reload apache2`。

## 7. 上线验证

把以下命令中的域名替换为自己的域名，在 Ubuntu SSH 中执行：

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://fly.example.com/
curl -sS -o /dev/null -w '%{http_code}\n' https://fly.example.com/assets/screens/customer.png
curl -sS -o /dev/null -w '%{http_code}\n' https://fly.example.com/config.php
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://fly.example.com/api/checkout
```

预期：首页和实际存在的截图返回 200；旧配置文件路径返回 404；未登录下单接口返回 401。请同时在电脑和手机浏览器打开首页、软件界面、功能和购买方案页面，确认图片比例正常、HTTPS 地址无证书警告，页面显示“价格待公布”或购买暂不可用。截图文件名如有调整，可以先运行 `ls /var/www/fly/public/assets/screens` 查看实际文件，再更换上面的检查路径。

## 8. 后续开放下载与购买

当前可以公开展示官网。购买接口尚未实现；`paymentReady()` 固定返回 false，修改销售开关不能开启付款。支付通知接口返回 410，返回页面不会确认付款。

正式收款前必须完成：

1. 服务端验证账户登录结果并绑定会话，不能从浏览器参数直接写入用户 ID。
2. 确定支付服务并实现独立适配器，包括服务端签名、金额/币种/收款账户核对、重复通知幂等和退款处理。
3. 确定基础版和高级版模块及价格。现价格配置单位为人民币分；若改用其他币种，必须同步修改方案、订单快照、展示及校验。客户端必须实际限制模块。
4. 将与客户端验签公钥匹配的 Ed25519 签发私钥放在 `/etc/fly/issuer.pem`，不放入网站或公开目录。限制文件访问权限并另做安全备份。
5. 验收登录、真实付款、设备授权、三设备上限、换机和退款流程，再实现并开启销售状态。当前预览版本不满足正式销售条件。

开放下载时，将已验收的安装包放在网站目录之外，例如 `/srv/fly-download/Fly-Setup.exe`，确保 `www-data` 可读，再配置 `SetEnv FLY_DOWNLOAD_FILE /srv/fly-download/Fly-Setup.exe`。未配置时 `/download` 返回 404。

## 9. 备份、更新和故障检查

### 数据备份

每次更新前以及开始收款后定期做 SQLite 一致性备份：

```bash
sudo install -d -o root -g root -m 700 /var/backups/fly
sudo sqlite3 /var/lib/fly/fly.sqlite ".backup '/var/backups/fly/fly-$(date +%Y%m%d-%H%M%S).sqlite'"
sudo ls -lh /var/backups/fly/
```

备份文件要定期下载到另一台设备或安全的对象存储；只有留在同一台服务器上的备份无法抵御服务器丢失。正式收款后还要安全备份 `/etc/fly/` 中的配置与密钥，限制备份访问权限。恢复数据库前先停止 Apache、备份现有数据库，再将备份复制回 `/var/lib/fly/fly.sqlite`，设置所有者为 `www-data:www-data`、权限为 `600`，最后启动 Apache。

### 网站更新

在 Windows 重新执行第 3 节的打包和上传。更新前先按上文备份数据库，再在 Ubuntu SSH 中备份当前网站文件：

```bash
sudo tar -czf "/var/backups/fly/site-$(date +%Y%m%d-%H%M%S).tar.gz" -C /var/www/fly public src issuer_public_key.txt
```

如果使用方法 A 上传 `web.zip`，重复第 3 节的解压和 `sudo cp -a` 安装步骤。如果使用方法 B 上传 `fly-web.tar.gz`，执行：

```bash
sudo tar -xzf ~/fly-web.tar.gz -C /var/www/fly
```

最后统一执行：

```bash
sudo chown -R root:root /var/www/fly
sudo find /var/www/fly -type d -exec chmod 755 {} +
sudo find /var/www/fly -type f -exec chmod 644 {} +
sudo apache2ctl configtest
sudo systemctl reload apache2
```

如需回滚网页文件，使用上一步生成的 `site-*.tar.gz` 覆盖解压并重载 Apache。未来如果版本引入数据库结构变更，回滚时还要按该版本迁移说明恢复对应数据库备份。

### 故障排查

```bash
sudo apache2ctl configtest
sudo systemctl status apache2 --no-pager
sudo tail -n 100 /var/log/apache2/fly-error.log
sudo journalctl -u apache2 -n 100 --no-pager
sudo ufw status verbose
```

常见问题：无法访问时检查域名解析、云安全组、UFW 和 Apache 状态；500 错误时检查 Apache 错误日志及 PHP 模块；数据库错误时检查 `/var/lib/fly` 的属主和权限；HTTPS 失败时确认域名解析和公网 80/443 端口；图片 404 时核对打包文件和实际路径。不要把错误日志、密钥或数据库放入 `public/`。

## 资料

- [Ubuntu：安装 Apache 与 PHP](https://ubuntu.com/server/docs/how-to/web-services/install-php/)
- [Ubuntu 24.04 PHP 软件包](https://packages.ubuntu.com/noble/php/)
- [Ubuntu：UFW 防火墙](https://ubuntu.com/server/docs/firewalls/)
- [Ubuntu 24.04 Certbot Apache 插件](https://packages.ubuntu.com/noble/python3-certbot-apache)
- [Certbot 官方说明](https://certbot.eff.org/instructions?ws=apache&os=snap)
