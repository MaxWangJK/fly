# Fly 安卓正式签名与备案材料

2026-10-16；包名 `com.flyproduct.fly`，应用版本仍为 `2.0.4+40`。本次建立长期应用发布签名，并对已验收的 40 版 APK 对齐、重签。没有改动业务程序或数据，没有提交备案申请、上架或部署。

## 可填写的信息

| 字段 | 值 |
| --- | --- |
| APP 包名 | `com.flyproduct.fly` |
| 签名 MD5（证书指纹） | `5E96E7B982BF8DB94FEF71F148BC0859` |
| 公钥 | [完整 RSA 模数](../handoff/apk/20261016/Fly-Android-Release-Public-Key.txt)，复制整行 |
| 证书 SHA-256 | `5240E834C4F5800EC22E9B882526A9CCBFE3366E334857CAE0154A0B66079EB2` |

[完整备案信息](../handoff/apk/20261016/Fly-Android-Release-Filing-Info.txt)、[公开证书](../handoff/apk/20261016/Fly-Android-Release-Certificate.cer)、[正式签名 APK](../../dist/Fly-2.0.4-build40-android-release-signed-20261016.apk)、[实际核验清单](../handoff/apk/20261016/manifest-Fly-Android-Release-20261016.json)。备案时使用这一组信息，原 Android Debug 测试证书 MD5 `D0A58DFC764BF184B0E641434E8B757F` 只对应旧测试包。

公开材料已随本次 Git 检查点保存；APK 本体在忽略的 `dist/`，迁移时另行复制。正式包、旧测试包及 Windows 包的大小和 SHA-256 见 [APK / Windows 迁移台账](../handoff/APK_RELEASES.md)。

本证书为 Android 应用的自签名发布证书，名称 `CN=Fly Android Release`，RSA 2048 / SHA256withRSA，有效期至 2054-03-03。MD5 是备案所需的证书指纹，签名算法本身没有使用 MD5。它不是服务器 HTTPS、书籍或离线授权证书，也不能用于 iOS 栏目。

## 密钥保管与后续构建

- 原件：`license_tools/private/android/fly-android-release.p12`；密码和别名配置在同目录 `signing.properties`。
- 初始本地副本：`license_tools/private/android/backups/20261016-initial/`。原件与副本哈希已核对；同磁盘副本不代替另一个安全存储位置的离线备份。
- 私有目录已限制 Windows 本机访问权限，密钥库本身用随机强密码加密；密码不显示在日志、命令参数或备案文件中。不要把私钥、密码配置或整个私有目录发给客户或上传公开仓库。
- 后续发布必须复用原件及密码配置。迁移 Mac/新电脑时将整个私有签名目录安全带走；这些文件被 Git 忽略，单独 clone 仓库不会取得它们。
- `android/app/build.gradle.kts` 已配置正式签名，公有指纹固定在 `android/release-certificate.sha256`。正式签名文件缺失或证书不符时应停止构建，不能通过生成新钥匙或回退测试签名解决。
- Windows 可运行 `scripts/build_android_release.ps1` 继续构建；Mac 使用正常 Flutter Android release 命令，Gradle 读取相同的相对路径配置。原书籍配置也须保留。

本 APK 为正式签名的备案核验包，沿用 40 版原有功能和测试授权设置；不代表商业收费、商店审核或备案审批已完成。

## 从测试版换装

旧测试版与正式签名不同，不能直接覆盖。可以先用本 APK 提交备案核验，不必为了取得公钥而卸载正在使用的测试版。

1. 如果手机测试版有数据，先保留它；通过电脑手机直连完成业务数据及实体文件同步，核对队列，并在电脑抽查记录、复盘和图片/附件是否真实可打开。绿色连接状态不能代替实体文件核对。
2. 在“设置→数据与备份”制作独立备份，保存到应用目录之外。增量文件备份还需要 ZIP 旁的 `.fly-file-objects`，不能只带走 ZIP。手机本机设置、未同步内容不能仅凭电脑有记录就认定已完整备份。
3. 只有确认重要内容均可恢复后，才考虑卸载测试版、安装正式签名版，再配对同步或恢复。存在未确认备份的手机独有数据时，继续保留旧版，不要先卸载。

## 已验证与边界

- 新 APK 的真实证书与发布密钥公开证书一致，旧测试证书不在新包中；v2/v3 签名验证通过，另以 API 23 校验范围验证 v1 签名。应用实际最低系统仍为 Android 7.0（API 24）。
- 16 KB 对齐、APK 完整性、包名/版本/三种 ABI、非调试属性已核对。353 个非签名 ZIP 条目与原 40 版逐项内容哈希一致；未包含私钥、密码配置和书籍内部配置文件。
- 应用业务回归沿用 2026-10-14 的 328 项通过记录，本次没有把旧记录冒称为重新执行的完整回归；本次重点验证签名及包内容一致性。未进行真机安装或数据迁移。

应用签名、公钥、证书指纹及密钥长期保管：[Android 官方签名说明](https://developer.android.com/studio/publish/app-signing)。

补充验证：Gradle `signingReport` 中 release 使用 `flyRelease`，证书 SHA-256 与实际 APK 一致；模拟正式签名配置缺失时，release 验证按预期停止；最终 Flutter 静态检查无问题，原件与本地备份再次核对一致。
