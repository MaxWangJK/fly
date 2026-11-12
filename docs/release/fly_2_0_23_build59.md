# Fly 2.0.23+59 Windows / Android

2026-11-12：按用户要求提交本轮资料库和文件操作功能，打包Windows10/11 x64与Android。构建源码`980f23ea3774b2a4c1e64b816270e7e52599e387`，2.0分支`codex/fly-2-sync`；最后交付文档提交用git log -1核对。

- 资料库默认隐藏，桌面可在“设置 → 导航”开启；保留已有书籍、笔记和阅读历史。
- 电脑文件页右下角“+”按内容区大小调整位置，在当前目录新建文件夹。
- 空白处右键新增查看（小图标/中图标/列表）、排序、粘贴和刷新；视图与排序沿用现有偏好。
- 粘贴支持普通文件及Fly内部剪切移动，保留重复文件确认。外部文件夹递归粘贴尚未实现，会提示跳过。

[功能与界面验证](desktop_files_context_20261112.md)。累计40项不同的相关用例和静态检查通过；提交后的源码另复验7项发布冒烟用例全部通过。没有重跑整套客户端或后台，也没有新增独立Windows10设备、Android真机或Apple验收。

Windows安装器、完整便携ZIP、原正式签名和原测试签名APK均构建并验证。核对了Windows实际程序版本、最低Windows10/x64设置、ZIP内容与SQLite/固定视频库；APK包名、版本代码59、三种ABI、非调试属性、原证书、Dart应用内版本、视频插件、ZIP完整性及16KB包对齐。两种APK的非签名内容一致，原书籍配置保持；没有打包邮件配置、签发私钥或真实业务库。

SQLite20、后台0005、依赖版本和功能测试授权配置保持，云同步仍不传实体文件。安卓正式签名表示沿用长期发布身份，不表示收费已启用；按手机已有签名选择覆盖升级包，首次安装可选正式签名。Windows安装器未配置发行代码签名。原网站和独立书稿工作区修改保留，未纳入本次提交；本轮没有后台部署或官网发布。

| 文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| [Fly-Setup-2.0.23-build59-testing.exe](../../dist/Fly-Setup-2.0.23-build59-testing.exe) | 19111178 | `DB30E7FE9AAFCC880EB363886BC4E721B1DBBB9AF8C54071FF66DBF351525CF5` |
| [Fly-2.0.23-build59-windows-test-20261112.zip](../../dist/Fly-2.0.23-build59-windows-test-20261112.zip) | 24081182 | `826EACA636654C7C85DC3F0119EDB106C6DCB54F993D35981466989003E0231B` |
| [Fly-2.0.23-build59-android-release-signed-20261112.apk](../../dist/Fly-2.0.23-build59-android-release-signed-20261112.apk) | 134430999 | `20BF2593CBAE547E2036736A2C7F8603C5517B6C7176ACBDD0D5E2BE2F3C1673` |
| [Fly-2.0.23-build59-android-test-20261112.apk](../../dist/Fly-2.0.23-build59-android-test-20261112.apk) | 134423855 | `D968ABCB7B8C76D2E768B7F0DD3ED1A655AF8984705C64789306B1743400FC38` |

[公开清单与备案](../handoff/apk/20261112-build59/README.md)。安装包和私有构建配置不在Git，迁移须单独带走。
