# Fly 2.0.24+60 · 视频卡顿修复交付

2026-11-12：按用户反馈修复播放视频及关闭后操作变慢，打包Windows10/11 x64和Android。构建源码`eab04c579145235585198f0cef015588ff604d31`，分支`codex/fly-2-sync`；最终交付文档提交用git log -1核对。

- 本地同步避免每2秒、每轮两次完整读取未变化的视频；耗时摘要计算移出界面线程，保留文件变化、下载完成及定期审计的完整校验。
- 视频画面与进度更新分离，避免频繁重建纹理子树；关闭、失败和重试增加暂停与释放保护，保留原视频内容、分辨率和解码器策略。
- Windows减少全量原生日志向Dart转发。播放器接口仍为6.9.0，仅由测试依赖改为运行时依赖；没有升级包或SDK。

[定位、实现与验证](video_performance_20261112.md)。43项不同的相关用例和全项目静态检查通过，包含断点续传、20MiB局域网双向传输、实际HTTP的两设备文件传输及三设备合并。另完成独立Windows原生样例播放/关闭三轮和64MiB合成文件AOT校验比较。没有重跑整套客户端或后台；用户原视频、独立Win10设备及Android真机仍由用户实测，Apple未构建。

Windows安装器、完整便携ZIP和两种原签名APK已构建并核验：实际程序及应用内版本、包名/版本代码60、三种ABI、非调试属性、原证书、ZIP完整性、16KB包对齐和非签名内容一致。便携包逐文件匹配本次Release输出，SQLite及固定视频DLL完整；原书籍配置保持，没有打包邮件配置、签发私钥或业务库。

SQLite20、后台0005和功能测试授权配置保持，云同步仍不传实体文件。安卓沿用原正式及原测试身份，按已有安装签名选择覆盖升级；首次安装可选正式签名包。Windows安装器没有发行代码签名。原网站和独立书稿修改保留，本轮没有部署后台或发布官网。

| 文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| [Fly-Setup-2.0.24-build60-testing.exe](../../dist/Fly-Setup-2.0.24-build60-testing.exe) | 19114454 | `23D1E01FF3CC86C9157CF05408A2B5D062D1CBD4D81B209392D70BE58D24EFE6` |
| [Fly-2.0.24-build60-windows-test-20261112.zip](../../dist/Fly-2.0.24-build60-windows-test-20261112.zip) | 24084269 | `3BDFD66EB984B5A7FC7EE4BAAC1E7E1A208DAA22DB8352779F5924C5895E84B0` |
| [Fly-2.0.24-build60-android-release-signed-20261112.apk](../../dist/Fly-2.0.24-build60-android-release-signed-20261112.apk) | 134463767 | `B81320D8EB06C9E7F85F32A7A0BA5E408118492333DD0B61839D5BC49126FF35` |
| [Fly-2.0.24-build60-android-test-20261112.apk](../../dist/Fly-2.0.24-build60-android-test-20261112.apk) | 134456623 | `F4E156F3A6356F4B19AF7EAFA83BA4491360CD250AA43E431313F5B023477B37` |

[公开清单与备案](../handoff/apk/20261112-build60/README.md)。安装包及原私有配置须安全单独迁移。
