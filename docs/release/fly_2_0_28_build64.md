# Fly 2.0.28+64 · 客户状态单击响应修复

2026-11-13：用户反馈客户状态点击比级别、来源慢约半秒，要求修复并打包Windows10和APK。源码`7269ffbf905b79c99c9b9804040a6e8f7267554c`，分支codex/fly-2-sync；最终文档提交用git log -1核对。

## 原因和修复

桌面状态标签外层的双击手势参与了手势竞争，普通单击要等双击判断窗口结束，初始窗口来自固定SDK的300毫秒常量；这解释了状态选择比普通级别/来源标签滞后的原因，不把用户感受到的半秒当成精确性能测量值。

改为被动观察指针序列，ChoiceChip沿用普通单击选择流程，松开后的首帧即可更新选中值；第二次有效点击仍可打开编辑。短定时器只清理点击历史，不延迟选中。只识别主按键和同一标签，右键、拖动与指针取消会清除判断，组件退出时清理定时器。手机仍仅选择状态，没有管理入口；角标位置、按钮范围、标签间距及历史状态保护保持。

## 验证范围

先在旧实现复现首帧断言失败：级别和来源正常，状态尚未选中。修复后8项不同交互/布局用例通过：5种平台/窗口的真实客户创建组件和3种布局；分别在普通点击后的首帧检查级别、来源和状态，覆盖Windows浅色/深色与大文字、Android横竖屏、iOS主机侧布局。桌面还验证双击改名、右键/拖动/取消不误编辑，以及原新增/确认删除、历史状态与草稿保留。全项目静态检查无问题。

首帧用例验证响应流程，不代替物理设备毫秒性能测量。没有重跑整套客户端/后台，没有新增真实同步网络、Apple编译或物理设备验收，没有读取真实业务库。通过后直接构建，未重复运行相同的发布烟测。

实际渲染：[桌面1264浅色](../handoff/verification/20261113-customer-status-instant/customer-status-instant-1264.png)、[桌面900深色大文字](../handoff/verification/20261113-customer-status-instant/customer-status-instant-900.png)、[Android390](../handoff/verification/20261113-customer-status-instant/customer-status-instant-390.png)、[Android横屏844](../handoff/verification/20261113-customer-status-instant/customer-status-instant-844.png)、[iOS布局430](../handoff/verification/20261113-customer-status-instant/customer-status-instant-430.png)。全部使用隔离测试数据，iOS图不代表Apple真机验收。

## 安装包

Windows10/11 x64安装器及完整便携ZIP，Android原正式和原测试签名APK已生成。实际程序及应用内版本、APK包名/版本代码64、三种ABI、非调试属性、原签名、16KB包对齐和两APK非签名内容一致已核验；便携包逐文件匹配Release输出，SQLite和固定视频DLL完整。未包含私有邮件配置、签发私钥或业务库。原书籍和功能测试授权配置、SQLite20、后台0005、依赖及SDK保持，云同步仍不传实体文件。

安卓按原安装身份覆盖升级；首次安装可用正式签名版。Windows安装器没有发行代码签名。没有独立Win10、Android真机或Apple构建/验收，没有部署后台或发布官网；原网站和独立书稿修改保留。

| 文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| [Fly-Setup-2.0.28-build64-testing.exe](../../dist/Fly-Setup-2.0.28-build64-testing.exe) | 19126258 | `35CDFB4BB0093732D42F728A1E2B170EB71DF58E429D0BF47BCFC06BA0C880B8` |
| [Fly-2.0.28-build64-windows-test-20261113.zip](../../dist/Fly-2.0.28-build64-windows-test-20261113.zip) | 24100698 | `13EF51D31D6EC3A50C9005B3CC5A37201B9F7DF0E6CF98717086609DF6736DE0` |
| [Fly-2.0.28-build64-android-release-signed-20261113.apk](../../dist/Fly-2.0.28-build64-android-release-signed-20261113.apk) | 134545687 | `9C49FF4A9F87B52323653D36E725289E7B04863B16776EEB599ACC9F3351D213` |
| [Fly-2.0.28-build64-android-test-20261113.apk](../../dist/Fly-2.0.28-build64-android-test-20261113.apk) | 134538543 | `35880E026BE509B77FFF8D6B86671274D1073B150E26E1EE55C15A8E584DDC29` |

[公开核验与备案](../handoff/apk/20261113-build64/README.md)。安装包、原私有配置和真实资料须安全单独迁移。
