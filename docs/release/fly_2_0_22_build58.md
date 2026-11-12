# Fly 2.0.22+58 Windows / Android

2026-11-12：按用户要求，将手机导入导出隐藏、电脑一级搜索入口移除和根目录文件夹快捷入口提交到2.0分支，打包Windows10/11 x64与Android。功能与48项相关回归、静态检查和渲染验证见[源码改动记录](navigation_folder_shortcuts_20261109.md)。

Android包含build50之后已完成的文件布局、图片连续浏览、视频播放、点击与拖放修复、匿名统计及更新检查；手机仍保留文件添加、图片、拍照与分享。云同步不传实体文件，SQLite20、后台0005、原书籍配置和安卓长期签名保持。Windows延续原功能测试授权配置。

构建源码`8660efcbf450a266ffb85c8e3c5bd46f3a84c591`；Windows安装器、完整便携ZIP、原正式签名APK及原测试签名APK均构建并核验。没有新增后台部署或Apple构建；原网站与独立书稿修改不纳入本次提交。


48项相关回归和静态检查沿用本轮已完成结果，没有重跑整套客户端或后台。Windows程序实际版本为2.0.22+58，安装器最低系统为Windows10、x64，ZIP及SQLite和固定视频DLL依赖完整。两种APK包名、版本代码58、原证书、三种ABI、非调试属性、Dart应用内版本、视频插件、非签名内容一致性、ZIP完整性和16KB包对齐均已验证。原书籍读取配置保持，未夹带邮件配置、签发私钥或真实业务库。

安卓正式签名是长期发布身份，不表示收费已开放；两个APK均沿用功能测试授权配置。按现有安装身份选择覆盖升级，首次安装可选择正式签名包。Windows安装器没有发行代码签名；本轮没有在独立Windows10设备或Android真机重复验收。

| 文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| [Fly-Setup-2.0.22-build58-testing.exe](../../dist/Fly-Setup-2.0.22-build58-testing.exe) | 19099385 | `ABE55AC5DF303A5CE34A97EDF5FA3D42D7D1F812B06E92536A3B5240A96DFA75` |
| [Fly-2.0.22-build58-windows-test-20261112.zip](../../dist/Fly-2.0.22-build58-windows-test-20261112.zip) | 24064960 | `D85DAE148140D8D82305DA5BC7A77E0D52D58C423CC46E00CD667D3616716316` |
| [Fly-2.0.22-build58-android-release-signed-20261112.apk](../../dist/Fly-2.0.22-build58-android-release-signed-20261112.apk) | 134414511 | `3F435F77EE7D2937FEEC5626A4658B231E34969F471F3FC19878A7A50DBE6DB1` |
| [Fly-2.0.22-build58-android-test-20261112.apk](../../dist/Fly-2.0.22-build58-android-test-20261112.apk) | 134407471 | `517DA63151124CE5ABC6DFA317B3389A1712CE0EFA25188D74F1072E485DF221` |

[公开清单与备案](../handoff/apk/20261112-build58/README.md)。源码与交付记录保存在2.0分支，最终文档提交以git log -1核对；Git不包含dist中的安装包及私有配置。
