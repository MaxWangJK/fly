# 官网安装包上传说明

官网导航的“下载 Fly”打开独立的 `/download` 页面，以三张卡片提供 Windows 10、Android、macOS 入口；首页下载区也显示相同的卡片。网站部署在 `/var/www/fly` 时，安装包统一放在 **`/var/www/fly/public/downloads/`**。这是对外公开的下载目录，只有准备公开发布的安装包可以放进去；不要放私钥、配置、数据库、源代码或客户资料。

更新下载页面时，需把本地 `web/src/site.php`、`web/public/index.php` 和 `web/public/assets/site.css` **一起**上传到服务器对应路径。新页面会按 CSS 文件内容生成版本号，让浏览器重新加载样式；若只上传 PHP 文件，卡片会失去布局样式。

| 平台 | 服务器上的完整路径 | 下载链接 |
| --- | --- | --- |
| Windows 10（64 位） | `/var/www/fly/public/downloads/Fly-Windows10-x64.exe` | `/downloads/Fly-Windows10-x64.exe` |
| Android | `/var/www/fly/public/downloads/Fly-Android.apk` | `/downloads/Fly-Android.apk` |
| macOS | `/var/www/fly/public/downloads/Fly-macOS.dmg` | `/downloads/Fly-macOS.dmg` |

**文件名大小写必须完全一致。**网站会检查每个文件是否存在、可读且非空；文件就绪后对应按钮自动显示，未上传的平台显示“安装包准备中”。文件必须是真正的 EXE、APK、DMG 格式，不能只修改扩展名。如果 Mac 最终是 PKG 或 ZIP，需要先调整 `web/src/site.php` 中对应文件名和页面文字。

## 上传步骤

`/var/www/fly` 的程序文件由 root 管理。先通过 SFTP 或云服务器的上传工具把安装包传到 SSH 用户的家目录，再在 Ubuntu 中执行以下命令；示例源文件位于 `~/`：

```bash
sudo install -d -o root -g root -m 755 /var/www/fly/public/downloads
sudo install -o root -g root -m 644 ~/Fly-Windows10-x64.exe /var/www/fly/public/downloads/Fly-Windows10-x64.exe
sudo install -o root -g root -m 644 ~/Fly-Android.apk /var/www/fly/public/downloads/Fly-Android.apk
sudo install -o root -g root -m 644 ~/Fly-macOS.dmg /var/www/fly/public/downloads/Fly-macOS.dmg
```

可以分批上传：尚未准备好的平台跳过相应 `sudo install` 命令。使用 root SSH 用户时，`~/` 是 `/root/`；使用普通用户时是 `/home/用户名/`。如果上传工具无法直接写入 `/var/www/fly/public/downloads/`，这是正常的，按上述两步操作即可。

若替换已有安装包，使用相同文件名覆盖。网站页面会在下一次请求时检查文件；一般不需要重启 Nginx 或 PHP-FPM。浏览器若缓存旧页面，强制刷新一次。

## 验证

以实际网站地址替换 `http://你的公网IP`；已有域名和证书时使用 `https://你的域名`：

```bash
ls -lh /var/www/fly/public/downloads/
curl -I http://你的公网IP/downloads/Fly-Windows10-x64.exe
curl -I http://你的公网IP/downloads/Fly-Android.apk
curl -I http://你的公网IP/downloads/Fly-macOS.dmg
```

已上传的安装包应返回 `200`，尚未上传的应返回 `404`。浏览器打开官网 `/download` 页面，再逐个测试按钮；Windows、Android、macOS 安装包还应分别在对应设备上完成安装验收。

大文件会由 Nginx 或 Apache 直接发送，不经过 PHP 读取。仓库只跟踪下载目录的占位文件，不跟踪实际安装包；若使用压缩整个 `web` 文件夹的方式更新网站，打包前仍要检查本地 `public/downloads/` 是否有安装包。更新官网代码时请保留服务器上的 `/var/www/fly/public/downloads/` 内容并单独备份安装包。
