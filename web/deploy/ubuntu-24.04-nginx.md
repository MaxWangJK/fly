# Fly 官网：已有 Nginx 时的 Ubuntu 24.04 部署

服务器已有 Nginx 占用 80/443 端口时，Fly 可以直接使用 **Nginx + PHP-FPM + SQLite**。不要再启动 Apache，也不要为了部署 Fly 停掉正在运行的 Nginx。文件上传和网站目录仍按 [主部署手册](ubuntu-24.04.md)第 1、3 节执行；Apache 专用的第 2、4、5、6 节改用以下步骤。

以下示例假设域名是 `fly.example.com`、网站文件已经安装到 `/var/www/fly`。把域名换成实际值。若现有 Nginx 已为同一域名配置了站点，应修改该站点配置，避免重复的 `server_name`。

## 1. 安装 PHP-FPM 并停用未运行的 Apache

```bash
sudo apt update
sudo apt install -y php8.3-fpm php8.3-cli php8.3-sqlite3 sqlite3 certbot python3-certbot-nginx
sudo systemctl disable --now apache2
sudo systemctl enable --now php8.3-fpm
php -m | grep -Ei 'openssl|pdo_sqlite|sodium'
sudo systemctl status php8.3-fpm --no-pager
ls -ld /etc/php/8.3/fpm/pool.d
```

检查结果应显示三个 PHP 扩展、服务状态 `active (running)`，并且 `/etc/php/8.3/fpm/pool.d` 目录存在。该目录由 `php8.3-fpm` 软件包自动创建；如果不存在，先确认安装命令成功，不要手动创建空目录。`disable --now apache2` 只针对 Apache，不会停止 Nginx。

## 2. 数据目录和 Fly 专用 PHP-FPM 池

如果已按主手册创建 `/var/lib/fly/fly.sqlite`，无需重复初始化。否则执行：

```bash
sudo install -d -o www-data -g www-data -m 700 /var/lib/fly
sudo -u www-data env FLY_DB_PATH=/var/lib/fly/fly.sqlite php -r 'require "/var/www/fly/src/Core.php"; FlyWeb\Database::connect(); echo "database OK\n";'
```

创建单独的 PHP-FPM 池，避免改变服务器上其他 PHP 网站的配置：

```bash
sudo nano /etc/php/8.3/fpm/pool.d/fly.conf
```

填写以下内容，把域名换成实际域名。**当前仍保持销售关闭和价格 0。**

```ini
[fly]
user = www-data
group = www-data
listen = /run/php/fly.sock
listen.owner = www-data
listen.group = www-data
pm = ondemand
pm.max_children = 5
pm.process_idle_timeout = 10s
pm.max_requests = 500
env[FLY_BASE_URL] = https://fly.example.com
env[FLY_DB_PATH] = /var/lib/fly/fly.sqlite
env[FLY_PRICE_BASIC_CENTS] = 0
env[FLY_PRICE_PRO_CENTS] = 0
env[FLY_SALES_ENABLED] = 0
env[FLY_ISSUER_PRIVATE_KEY_FILE] = /etc/fly/issuer.pem
```

如果之前按 Apache 手册创建了 `/etc/fly/apache-env.conf`，Nginx/PHP-FPM **不会读取**它；以此处的 FPM 配置为准。保存并检查：

```bash
sudo php-fpm8.3 -t
sudo systemctl restart php8.3-fpm
sudo test -S /run/php/fly.sock
```

生产私钥将来仍应放在网站目录外，例如 `/etc/fly/issuer.pem`，并限制为 `root:www-data`、权限 `640`。现在没有登录和支付功能，不需要上传私钥。

## 3. 创建 Nginx 站点

先检查现有站点，确认该域名没有重复配置：

```bash
sudo nginx -T 2>&1 | grep -n 'server_name'
```

新域名可创建：

```bash
sudo nano /etc/nginx/sites-available/fly
```

填写：

```nginx
server {
    listen 80;
    server_name fly.example.com;
    root /var/www/fly/public;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /index.php {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /var/www/fly/public/index.php;
        fastcgi_pass unix:/run/php/fly.sock;
    }

    location ~ \.php$ {
        return 404;
    }

    location ~ /\.(?!well-known(?:/|$)) {
        deny all;
    }
}
```

Nginx 不读取 `public/.htaccess`；上面的 `try_files` 负责把 `/account`、`/download` 等路径交给 PHP。只有 `index.php` 可以被 PHP-FPM 执行，其他 `.php` 路径返回 404。

启用新站点，先检查配置再重载正在运行的 Nginx：

```bash
sudo ln -s /etc/nginx/sites-available/fly /etc/nginx/sites-enabled/fly
sudo nginx -t
sudo systemctl reload nginx
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: fly.example.com' http://127.0.0.1/
```

如果软链接已存在，不要重复创建，直接运行后面三条命令。`nginx -t` 必须显示配置有效；如 Nginx 报重复域名，找到现有域名配置后合并，不要保留两个相同的 `server_name`。

## 4. 配置 HTTPS

确认域名 A 记录指向服务器公网 IP，云安全组与 UFW 都放通 TCP 80/443，再执行：

```bash
sudo certbot --nginx -d fly.example.com --redirect
sudo nginx -t
sudo systemctl reload nginx
sudo certbot renew --dry-run
```

检查 Certbot 生成的 HTTPS 站点仍使用 `/var/www/fly/public` 和 `/run/php/fly.sock`。如果已有同一域名证书，先查看 `sudo certbot certificates`，避免重复申请。

## 5. 检查网站

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://fly.example.com/
curl -sS -o /dev/null -w '%{http_code}\n' https://fly.example.com/assets/screens/customer.png
curl -sS -o /dev/null -w '%{http_code}\n' https://fly.example.com/config.php
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://fly.example.com/api/checkout
```

预期首页和图片为 200，`config.php` 为 404，未登录的下单接口为 401。请在浏览器中检查首页、客户中心、截图和 HTTPS 证书。

如果出现 502，检查 `sudo systemctl status php8.3-fpm --no-pager`、`sudo ls -l /run/php/fly.sock` 和 `sudo tail -n 100 /var/log/nginx/error.log`；如果出现 500，检查 PHP-FPM 日志和网站文件权限。

如果浏览器显示 **Apache2 Default Page**，先不要根据页面标题判断当前运行的是 Apache：Nginx 的默认站点也可能正在提供 `/var/www/html/index.html` 这份旧页面。先执行：

```bash
sudo ss -ltnp '( sport = :80 or sport = :443 )'
sudo nginx -t
sudo nginx -T 2>&1 | grep -nE 'server_name|root /var/www|listen .*default_server'
sudo ls -l /etc/nginx/sites-enabled/
sudo ls -l /var/www/fly/public/index.php
```

如果 `nginx` 正在监听 80/443，而浏览器访问的是服务器 **IP 地址**，请求通常会落到 Nginx 默认站点。应访问 `fly.conf` 中 `server_name` 指定的真实域名；确保域名 A 记录指向该服务器，并确认该域名的站点配置已经启用。只有确认默认站点不承载其他业务后，才考虑取消 `/etc/nginx/sites-enabled/default` 的启用。若是 `apache2` 正在监听，先查看 `sudo apache2ctl -S` 和 `sudo systemctl status apache2 --no-pager`，核对实际启用的网站与端口配置。

若 `/etc/nginx/sites-enabled/` 中只有 `default` 和 `fly`，且 `default` 只是 Ubuntu 欢迎页，可以取消它的软链接，让 Fly 成为 IP 请求的默认站点。此操作保留 `/etc/nginx/sites-available/default` 原文件，必要时可以重新启用：

```bash
sudo unlink /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
curl -sS -o /dev/null -w '%{http_code}\n' http://实际公网IP/
```

如果 `nginx -t` 失败，先不要重载；需要恢复时执行 `sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default`，再检查配置。若仍看到旧页面，用浏览器无痕窗口或执行 `curl -sS http://实际公网IP/ | head -n 8` 排除浏览器缓存。

### 暂时只用服务器 IP 预览

如果域名尚未配置，可以让 Fly 的 Nginx 站点**仅匹配该服务器的公网 IP**，无需删除默认站点。此步骤仅适用于上面的端口检查确认 **Nginx** 正在监听 80 端口的情况。

1. 编辑 `/etc/nginx/sites-available/fly`：把 `server_name fly.example.com;` 改为 `server_name 实际公网IP;`，保留其他配置不变。
2. 编辑 `/etc/php/8.3/fpm/pool.d/fly.conf`：把 `env[FLY_BASE_URL] = https://fly.example.com` 改为 `env[FLY_BASE_URL] = http://实际公网IP`。若仍是 HTTP，不要填 `https://`。
3. 检查并重载：

   ```bash
   sudo nginx -t
   sudo php-fpm8.3 -t
   sudo systemctl restart php8.3-fpm
   sudo systemctl reload nginx
   curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: 实际公网IP' http://127.0.0.1/
   ```

4. 浏览器访问 `http://实际公网IP/`。等域名 A 记录生效后，把这两处 IP 改回域名及 `https://域名`，再按第 4 节申请 HTTPS 证书。

之后更新网站文件时，仍按主手册第 9 节备份和覆盖文件，最后使用 `sudo nginx -t && sudo systemctl reload nginx`；修改 FPM 池配置后用 `sudo php-fpm8.3 -t && sudo systemctl restart php8.3-fpm`。数据库备份方式与主手册一致。

## 资料

- [Ubuntu 24.04 PHP-FPM 软件包](https://packages.ubuntu.com/noble/php8.3-fpm)
- [Ubuntu 24.04 Certbot Nginx 插件](https://packages.ubuntu.com/noble/python3-certbot-nginx)
