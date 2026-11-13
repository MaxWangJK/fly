# Fly 2.0.25+61 · Windows / Android修复交付

2026-11-13：按用户要求打包Windows与APK、提交Git。源码`ef10d479a0ab2bfb22d077025fa3cb4d3ff821bf`，分支`codex/fly-2-sync`；最终文档提交用git log -1核对。

- 文件管理重命名同时更新Fly管理的磁盘文件、打开/分享名称及本机路径。省略扩展名时保留原类型，同名目标不覆盖；数据库写入失败时恢复旧名。外部导入原件保持。
- 局域网另一设备已有文件时，根据接收的新名称原地改名；保留内容与摘要，不为改名重新下载同一份数据。
- 新建客户的姓名标签增加安全边距，表单提供滚动条；桌面批量导入/Excel模板固定在底部，取消和创建保持可用。手机继续隐藏导入导出。

[实现和界面证据](file_rename_customer_layout_20261112.md)。50项不同的相关回归和全项目静态检查于2026-11-12通过，含实际两设备局域网改名及20MiB双向传输。2026-11-13对本次已提交源码重复复验12项实体改名/弹框关键用例通过，不重复计为新增用例。没有重跑整套客户端或后台，没有读取真实业务库或用户原文件。

Windows10/11 x64安装器和完整便携ZIP、Android原正式及原测试签名包已生成。已核对实际程序及应用内版本、APK包名/版本代码61、三种ABI、非调试属性、原签名身份、16KB包对齐、两个APK非签名内容一致；便携包逐文件匹配Release输出，SQLite与固定视频DLL完整。未包含邮件配置、签发私钥或业务库。原书籍配置、功能测试授权配置、SQLite20与后台0005保持，云同步仍不传实体文件。

按现有安卓安装身份选择覆盖升级，首次安装可选正式签名版。Windows安装器没有发行代码签名；独立Win10设备、Android真机与Apple没有新增验收或构建。原网站/书稿修改保留，本轮没有部署后台或发布官网。

| 文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| [Fly-Setup-2.0.25-build61-testing.exe](../../dist/Fly-Setup-2.0.25-build61-testing.exe) | 19117434 | `22C8DF9AF8CA7DBC047418041B445DE18E4AA01D7084E5520BE80274D41A7433` |
| [Fly-2.0.25-build61-windows-test-20261113.zip](../../dist/Fly-2.0.25-build61-windows-test-20261113.zip) | 24088663 | `68A8943F5221FC9DF5DCC3336293A3EA29A97719C392F372DABCA4C61F2F493D` |
| [Fly-2.0.25-build61-android-release-signed-20261113.apk](../../dist/Fly-2.0.25-build61-android-release-signed-20261113.apk) | 134529303 | `B935921C03F185E8722AD0EF3F37B17F74AE0EBA3F61C482C5F8FA4A8892B9A8` |
| [Fly-2.0.25-build61-android-test-20261113.apk](../../dist/Fly-2.0.25-build61-android-test-20261113.apk) | 134522159 | `63FFE9300A483CB05D71810E81A7AD136A9591260C20D99B8110DECCC4C1A6FA` |

[公开核验与备案](../handoff/apk/20261113-build61/README.md)。安装包、真实数据和原私有配置须安全单独迁移。
