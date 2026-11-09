# Windows / Android 更新检查

2026-11-09，Fly 2.0.21+57。打开应用后后台检查一次；有较新版本时在顶部显示可关闭的提示，用户点“下载更新”才打开系统浏览器下载。在“设置 → 关于”也可手动检查、下载。自动检查失败静默，手动检查说明失败并允许重试。稍后仅隐藏本次启动提醒。

下载完成后用户运行 Windows 安装器，或在 Android 浏览器下载列表打开 APK，由系统完成安装与必要确认。没有静默安装、后台补丁、安装包自动执行或新增安装权限。Android 必须使用原长期发布签名，包名不变；不同签名无法直接覆盖。当前 iOS/macOS 没有此分发通道。

## 上传与命名

服务端扫描 `RELEASE_DIRECTORY`，原生默认 `/var/www/fly/public/downloads`，复用官网下载目录；不是同步实体文件目录。仅扫描这一层的普通文件，忽略软链接、空文件、测试/beta/临时文件和 ZIP。

| 可发布名称示例 | 含义 |
| --- | --- |
| Fly-2.1.exe / Fly-3.0.exe | Windows 2.1.0 / 3.0.0 |
| Fly-2.0.21-build57.exe | 同语义版本按 build 号比较 |
| Fly-Setup-2.0.21-build57-windows.exe | 可选 Setup 与平台后缀 |
| Fly-2.1.apk / Fly-2.0.21-build57-android.apk | Android |

版本数字比较，2.10 大于 2.9；无 build 按 0。名称需要与**实际包内版本**一致，后台不会读取 EXE/APK 内部版本。本轮交付名包含 `testing`，不会自动发布给全部用户；确认验收后复制成合规正式名再上传。撤下最高版本文件后会自动使用目录中下一份，无需改数据库或重启；客户端不会提示降级。

上传时先用 `.part` 名，传完再在同目录原子改名，防止未完成包进入目录。API 首次计算 SHA-256，随后按路径、大小、修改时间缓存；更换同名文件后重新计算。建议每次版本升级用新文件名，避免浏览器旧缓存。

## API

```http
GET /api/updates/latest/windows
GET /api/updates/latest/android
GET /api/updates/download/Fly-3.0.exe
```

查询示例：

```json
{"latest":{"version":"3.0.0","build":0,"fileName":"Fly-3.0.exe","size":123456,"sha256":"64位十六进制SHA256","downloadPath":"/api/updates/download/Fly-3.0.exe"}}
```

没有候选时 `{"latest":null}`；不支持的平台返回 400。客户端验证元数据、平台扩展名和同源下载路径，只向统一官方更新服务发送平台路径，**不发送匿名编号、当前版本、账号或业务数据**。客户端本地比较版本，5 秒超时。SHA-256 提供下载文件核验信息；当前通过浏览器下载，不宣称应用内完成文件校验或发行签名验证。

更新接口与匿名统计接口分离：更新需要区分 EXE/APK，统计仍只有随机编号与 1/2，没有平台/版本统计。自建同步服务器不会自动成为更新来源。

部署命令及 Nginx 配置见 [后台更新指南](../server/deploy/analytics-updates.md)。
