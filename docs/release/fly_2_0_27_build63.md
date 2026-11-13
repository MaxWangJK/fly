# Fly 2.0.27+63 · 客户状态交互与两端打包

2026-11-13，用户要求手机移除状态新增、编辑、删除，桌面精简红叉与悬停范围、恢复舒服的标签间距，并打包Windows和APK。源码`e412a1290beed7c410f4bfe192a3b8c89d383841`，分支codex/fly-2-sync；最终文档提交用git log -1核对。

- Android和iOS的新建客户只提供状态选择；不显示加号、红叉、编辑提示，长按和双击都不打开编辑框。电脑同步过来的自定义状态仍可选择，改名后仍保留草稿选择。
- 桌面保留末尾新增和双击改名，删除为右上角独立小圆形按钮，悬停与点击范围为20×20，不占整块标签。恢复常规标签内边距及8像素可见间隔，支持长名称换行。
- 删除仍需确认，只停用选项，历史客户保留原状态；导入确认时自动创建/复用级别与状态保持。

18项不同相关用例通过：5种平台/尺寸的真实客户弹框交互、3种客户弹框布局、9项导入及1项两数据库状态协议同步。覆盖桌面标签选择与小角标范围、双击编辑、删除取消/确认、历史客户、草稿保留，手机无管理入口/长按双击不编辑、自定义状态可选及改名后选择保持。全项目静态检查无问题；提交后重复复验8项界面关键用例，不另计。没有重跑整套客户端/后台或真实云服务器同步，没有读取真实业务库。

实际渲染检查：[桌面1264×681浅色](../handoff/verification/20261113-customer-status-refined/customer-status-refined-1264.png)、[桌面900×700深色及1.3倍文字](../handoff/verification/20261113-customer-status-refined/customer-status-refined-900.png)、[桌面角标悬停](../handoff/verification/20261113-customer-status-refined/customer-status-refined-hover-1264.png)、[Android390×844](../handoff/verification/20261113-customer-status-refined/customer-status-refined-390.png)、[Android844×390横屏](../handoff/verification/20261113-customer-status-refined/customer-status-refined-844.png)、[iOS430×932布局](../handoff/verification/20261113-customer-status-refined/customer-status-refined-430.png)。均为隔离测试数据。iOS为主机侧布局模拟，不代表Apple构建或真机验收。

Windows10/11 x64安装器和完整便携ZIP、Android原正式及原测试签名APK均已生成并核验。检查实际程序及应用内版本、APK包名/版本代码63、三种ABI、非调试属性、原签名、16KB包对齐及两APK非签名内容一致；便携包逐文件匹配Release输出，SQLite和固定视频DLL完整。未包含私有邮件配置、签发私钥或业务库。原书籍和功能测试授权配置、SQLite20、后台0005、依赖及SDK保持；云同步仍不传实体文件。

按原安卓安装身份覆盖升级；首次安装可用正式签名版。Windows安装器没有发行代码签名，没有新增独立Win10设备、Android真机或Apple构建/验收，没有部署后台或发布官网。原网站与独立书稿修改保留。

| 文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| [Fly-Setup-2.0.27-build63-testing.exe](../../dist/Fly-Setup-2.0.27-build63-testing.exe) | 19127680 | `E62A9D81F036A42EFCB88A850A458EF96EFD83390681829A4274DD07B4625F1A` |
| [Fly-2.0.27-build63-windows-test-20261113.zip](../../dist/Fly-2.0.27-build63-windows-test-20261113.zip) | 24101944 | `8A4B7ACE247A3335B4BADEE52B0771085B3DF5070BDB3DABDE4ACCB075A2CD36` |
| [Fly-2.0.27-build63-android-release-signed-20261113.apk](../../dist/Fly-2.0.27-build63-android-release-signed-20261113.apk) | 134545687 | `22965B2273A9EE3195456CFF244950A14A0FA6D526CC3686821B69F32CD8EB89` |
| [Fly-2.0.27-build63-android-test-20261113.apk](../../dist/Fly-2.0.27-build63-android-test-20261113.apk) | 134538543 | `F3C7E6D874349622CFD88E13D00C211E6BAA871A50ECFBB020E8BDFAD9B0A9C8` |

[公开核验与备案](../handoff/apk/20261113-build63/README.md)。私有配置、安装包和真实资料须安全单独迁移。
