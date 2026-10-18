# Fly 安装包、安卓备案与迁移台账

最后核对：2026-10-18；源码 `2.0.6+42`，schema 19，分支 `codex/fly-2-sync`。本轮安卓已重新编译并核验；Windows 和 Android 均为 build 42。本轮源码及内部发码工具已保存于功能检查点 `311c7b3`；原构建日期和哈希保持不变。完整功能需求见 [FLY_REQUIREMENTS.md](FLY_REQUIREMENTS.md)，迁移步骤见 [MAC_TRANSFER.md](MAC_TRANSFER.md)。

## 1. 当前应使用哪一个 APK

| 用途 | 文件（在工程 `dist/`） | 版本 | 文件字节数 | 证书 MD5 |
| --- | --- | --- | --- | --- |
| 正式签名备案核验 | `Fly-2.0.6-build42-android-release-signed-20261017.apk` | 2.0.6 / 42 | 93,813,852 | `5E96E7B982BF8DB94FEF71F148BC0859` |
| 原功能测试 / 保留原测试签名 | `Fly-2.0.6-build42-android-test-20261017.apk` | 2.0.6 / 42 | 93,843,887 | `D0A58DFC764BF184B0E641434E8B757F` |

本轮两个 build 42 包的程序内容一致，但证书不同，**不能互相覆盖升级**。原 build 37～41 测试版请选择本轮测试签名包覆盖升级；已安装正式签名版则选正式包。备案使用正式包对应的下列信息。保留旧测试安装及其唯一数据；换装前先完成业务与实体文件同步、检查队列和附件实际可打开，并在应用目录之外制作可恢复的完整备份。增量备份还需 ZIP 旁的 `.fly-file-objects`。详见 [换装说明](../release/android_release_signing_20261016.md)。

本包为正式签名的备案核验包。备案申请未提交、商店未上架，本地付费限制开关仍为测试配置 `ENABLE_LOCAL_LICENSE=false`；不能据此认定商业收费功能已验收。

## 2. 正式安卓备案信息

| 字段 | 实际值 |
| --- | --- |
| APP 名称 | Fly |
| APP 包名 | `com.flyproduct.fly` |
| versionName / versionCode | `2.0.6` / `42` |
| 签名 MD5（证书指纹） | `5E96E7B982BF8DB94FEF71F148BC0859` |
| 完整公钥（RSA 2048 位模数） | [复制此文件整行](apk/20261016/Fly-Android-Release-Public-Key.txt) |
| 证书 SHA-1（安卓证书） | `9E8BC6EFA12D280843F92FD7E1DCAE22AD70008F` |
| 证书 SHA-256 | `5240E834C4F5800EC22E9B882526A9CCBFE3366E334857CAE0154A0B66079EB2` |
| 证书名称 / 到期日 | `CN=Fly Android Release` / 2054-03-03 |
| 签名算法 | RSA 2048 / SHA256withRSA |
| 系统要求 / 目标 SDK | Android 7.0+（API 24）/ API 36 |
| CPU 架构 | arm64-v8a、armeabi-v7a、x86_64 |

[当前可复制备案字段](apk/20261017/Fly-Android-Release-Filing-Info-build42.txt)、[DER 公有证书](apk/20261016/Fly-Android-Release-Certificate.cer)、[PEM 公有证书](apk/20261016/Fly-Android-Release-Certificate.pem)、[本轮构建及包核验清单](apk/20261017/manifest-Fly-2.0.6-build42.json) 已整理到交接目录；公开材料已随功能检查点保存，安装包本体仍需另行复制。这里没有私钥或密码。

备案签名 MD5 是证书指纹，不是 APK 文件 MD5，也不是公钥 MD5；下节的 SHA-256 则用于核对安装包文件。以上安卓证书、公钥不能填写到 iOS 栏目。

## 3. 当前交付文件 SHA-256

以下文件都在 `dist/`，本体被 Git 忽略，需要随本人迁移归档另行带走。

| 文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| [正式签名 APK](../../dist/Fly-2.0.6-build42-android-release-signed-20261017.apk) | 93,813,852 | `8B49AEEA22AD86CC4BE05B60E6FDD4864C5367C7813361EC996015BD8461F019` |
| [原测试 APK](../../dist/Fly-2.0.6-build42-android-test-20261017.apk) | 93,843,887 | `033DA959C3035DA23627EC47158F34CEE8F5490077E0F76CEA2ECF0E1EEB6937` |
| [Windows 测试安装器](../../dist/Fly-Setup-2.0.6-build42-testing.exe) | 13,353,143 | `AF558D169675089E0ADF045DA639917848C4551D330B6FF831A01358E4983FD1` |
| [Windows 测试便携 ZIP](../../dist/Fly-2.0.6-build42-windows-test-20261017.zip) | 15,932,276 | `986A47CF805E60E3B35E4A6949CD75EE90868BC86EBA43BDAB262C427F2B5F87` |
| [外贸书籍 v1](../../dist/Fly-Foreign-Trade-Fieldbook-v1.fly) | 114,856 | `7C27E28E1E687487F8F51EC0D353CF02FDD154B87C0916976BA38ACD956A1EB1` |

[原 build 40 构建清单副本](apk/20261016/manifest-Fly-2.0.4-build40.json) 保留构建时的源码基线和工作区状态，不能把其 `sourceBaseCommit` 当作本次检查点的提交号。当前 Git 提交用 `git log -1 --oneline` 查看。

Windows 可使用 `Get-FileHash -Algorithm SHA256 <文件路径>`；Mac 可使用 `shasum -a 256 <文件路径>`。结果忽略大小写；大小或哈希不符时先找回完整文件，不将异常文件作为相同版本分发。

## 4. 原签名身份与新电脑构建

1. 安全转移原 `license_tools/private/android/`，含 `.p12` 密钥库、`signing.properties` 及初始备份。密码不写进本台账，不发给客户，不上传仓库。现有备份与原件一致，但同磁盘备份不能代替独立安全备份。
2. 同时保留原书籍内部配置 `license_tools/private/book_build_defines.json`、发布 seed 和其他必要授权原密钥；不要为了补缺文件重新生成替代。
3. `android/release-certificate.sha256` 固定公有证书指纹；Gradle 从原相对路径读取签名配置，也支持 `FLY_ANDROID_SIGNING_PROPERTIES` 指向原配置。缺失或证书不符时正式构建应停止。不要退回 debug 签名。
4. Windows 发布入口为 `scripts/build_android_release.ps1`；Mac 另装本机 Flutter、Java、Android SDK，并保持原构建参数与书籍内部配置。Windows SDK、缓存和 venv 不能作为 Mac 工具链复用。
5. 构建后重新从实际 APK 核对包名、版本、证书及文件哈希，再更新本台账；未来正常发版递增版本，不用新证书解决安装问题。

**iOS 状态：**项目 Bundle ID 为 `com.flyproduct.fly`。本机尚无真实 iOS 发布证书，未生成可备案的 iOS 公钥/签名 SHA-1，也未完成 Apple 平台编译与真机验收。迁移到 Mac 后使用实际开发者账户和发布证书核对，安卓密钥不适用。

## 5. 验证记录与剩余验收

- 2026-10-17 build 42：完整客户端 352 项通过，最终静态分析无问题；含临时 HTTP 双端、20 MiB LAN 文件、客户文件新增实体/子目录、返回、网格、手机“我的”及复盘卡片读写/清空/同步刷新。临时服务已关闭。
- Windows release、安装器和便携 ZIP 构建成功，原 SQLite 相对绑定、书籍配置、运行库文件及 ZIP 完整性核验通过；Windows 安装器未作发行代码签名。
- 两份 Android APK 原签名身份、2.0.6/42、API 24/36、三种 ABI、非调试属性、16 KB 对齐和完整性通过；353 个非签名条目哈希一致，无私有配置文件或内部发码工具。
- 横竖屏、300/360/430/844 目录宽度、手机/电脑复盘及窄屏 1.3 倍文字深色模式已自动验证和截图检查。系统权限、扫码、相机、分享、外部打开及厂商切口仍需真机确认。
- 原 build 40/41 二进制、公开材料和签名保留；未安装/卸载用户设备，未写入真实业务数据，未提交 Git、推送、部署、备案或 Apple 构建。

详细变化见 [build 42](../release/fly_2_0_6_build42.md)，证据见 [公开清单](apk/20261017/manifest-Fly-2.0.6-build42.json)。

2026-10-18 续补：上述“未提交 Git”是构建当日状态。现已保存于 `311c7b3`，仅重新核对归档，没有重建包或更换签名；见 [提交记录](../release/git_checkpoint_20261018.md)。
