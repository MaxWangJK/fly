# Fly 安装包、安卓备案与迁移台账

## 最新Windows / Android build62（2026-11-13）

Windows/Android2.0.26+62，包含导入自动创建级别/状态及状态新增、改名、停用和历史名称保留。48项相关用例与静态检查、6项重复界面复验、12项提交后重复复验、两端构建及原签名/包核验通过。两端均需更新，按原安卓签名覆盖升级；没有新增真机或Apple验收。[交付](../release/fly_2_0_26_build62.md) / [备案](apk/20261113-build62/README.md)。

## 历史Windows / Android build61（2026-11-13）

Windows/Android2.0.25+61，包含实体文件改名与客户创建弹框修复；50项相关用例和静态检查、12项重复发布复验、两端构建与原签名/包核验通过。原正式和原测试身份保持，按已有签名覆盖升级；没有新增物理手机或Apple验收。[交付](../release/fly_2_0_25_build61.md) / [备案](apk/20261113-build61/README.md)。

## 历史Windows / Android build60（2026-11-12）

两端2.0.24+60，修复大视频反复校验、播放器重复刷新及退出/错误资源释放。43项相关用例、静态检查、原生Windows样例与AOT合成验证、两端构建及包核验通过；保留原正式/原测试签名，按现有身份覆盖升级。用户原视频与手机真机待测试。[下载及验证](../release/fly_2_0_24_build60.md)、[备案](apk/20261112-build60/README.md)。

## 历史Windows / Android build59（2026-11-12）

两端2.0.23+59，包含资料库默认隐藏、桌面文件新建文件夹“+”及空白处查看/排序/粘贴/刷新菜单。40项不同的相关用例、7项提交后复验、静态检查及两端构建和包核验通过。原正式/原测试签名保持，按现有身份选择覆盖升级；没有新增真机或Apple验收。[下载及验证](../release/fly_2_0_23_build59.md)、[公开清单与备案](apk/20261112-build59/README.md)。

## 历史Windows / Android build58（2026-11-12）

两端2.0.22+58，包含手机导入导出隐藏、一级搜索移除及根目录快捷入口；安卓同时包含build50之后的已完成功能。原正式/原测试签名保持，按已有安装身份选择覆盖升级包。48项相关回归、静态检查、两端构建及包核验通过；没有新增真机或Apple验收。[下载及验证](../release/fly_2_0_22_build58.md)、[公开清单与备案](apk/20261112-build58/README.md)。


## 历史Windows build57（2026-11-09）

Windows2.0.21+57新增匿名统计、简单客户Excel导入和更新检测；后台0005原生包同步交付。客户端全量539通过/3跳过、后台86通过，应用静态检查及Windows构建和包核验通过。Android仍build50及原签名，不含本轮新客户端功能，Apple未编译。[安装包与验证](../release/anonymous_import_updates_20261109.md)。

## 历史Windows build56（2026-11-07，仅Windows）

Windows2.0.20+56修复文件单击轻移误触拖放与自身回落导入，并补回扁平文件夹内部移动。60项相关回归及静态检查、Windows构建/包核验通过；实际OLE接收软件待用户验收。Android仍build50及原两种签名，Apple未编译。[下载与验证](../release/file_click_drag_20261107.md)。

## 历史Windows build55（2026-11-07，仅Windows）

Windows2.0.19+55新增图片连续浏览与基础视频播放，包含视频插件DLL。iOS导入转换仅完成原生实现代码，尚无Xcode编译及iPhone验收；Live单卡归组未实现。Android仍build50和原两种签名，备案字段保持。[下载、验证与边界](../release/media_viewers_20261107.md)。


## 历史Windows build54（2026-11-07，仅Windows）

Windows2.0.18+54移除文件右上角小图标并统一带底色缩略图，横竖图完整显示，PDF使用同尺寸底框。本轮不构建安卓，保留build50及原两种签名，备案字段保持。[下载及验证](../release/file_thumbnail_frames_20261107.md)。


## 历史Windows build53（2026-11-07，仅Windows）

Windows2.0.17+53包含搜索下方路径、右侧文件设置、彩色文件夹列表、长名称保留扩展名及整组文件夹移动。本轮延续仅Windows，安卓仍build50和原两种签名，备案字段保持。[下载及验证](../release/file_navigation_20261107.md)。


## 历史Windows build52（2026-11-07，仅Windows）

Windows2.0.16+52包含客户详情PI开单弹框和紧凑文件夹/大缩略图；文档为类型封面，不是PDF正文缩略图。本轮延续仅打包Windows，安卓最新仍build50及原两种签名，备案字段未改。[下载及验证](../release/customer_files_20261107.md)。


## 历史Windows build51（2026-11-07，仅Windows）

Windows2.0.15+51修复手动12×20按一整组240件展示、允许超出柜体并标红。按用户要求只构建Windows，安卓最新仍为下面build50及原两种签名；没有新增安卓包或更改备案字段。[下载及验证](../release/manual_grid_20261107.md)。


## 当前Android / 历史Windows build50（2026-11-07）

Windows/Android2.0.14+50修复输入连续性，保留原两种安卓签名、包名及备案证书。按已有安装身份选择正式包或原测试升级包，不混用覆盖。
[下载、修复和核验](../release/input_continuity_20261107.md)、[build50公开清单与备案](apk/20261107-build50/README.md)。SQLite20、后台0004不变；Git不包含安装包与私有配置，真机输入法仍需用户验收。


## 历史Windows build49（2026-11-06）

Windows2.0.13+49提供A/B区域添加与剖面右键XYZ旋转/移除，[下载及校验](../release/cargo_areas_20261106.md)。Android本轮没有重建，最新仍2.0.10+46及原两种签名；安卓备案信息不变。


## 历史Windows build48（2026-11-06）

Windows2.0.12+48修复清空数量、0件计算与每组移除，[下载与校验](../release/cargo_quantity_20261106.md)。Android没有重建，最新仍2.0.10+46及原两种签名；备案字段不因Windows版本改变。


## 历史Windows build47（2026-11-06）

Windows2.0.11+47修复装柜剩余空间，[下载与校验](../release/container_spaces_20261106.md)。Android本轮没有重建，最新仍为下面的2.0.10+46及原两种签名，备案字段没有因Windows版本变化而改动。


## 历史build46（2026-11-02）

版本**2.0.10+46**，源码`2d0c95ff7b81d3cb73b817a4858b657602ebf993`，SQLite20、后台0004不变。Windows/Android已核验，相关回归47项通过，静态检查无问题；未重跑整套客户端。源码及文档提交推送2.0分支，原签名和书籍配置不变，真机仍需验收。

[交付及下载](../release/fly_2_0_10_build46.md)、[备案与哈希](apk/20261102-build46/README.md)。按现有签名选择正式/原测试升级包，不能混用覆盖。dist包和私有配置不随Git。

---


## 历史build45（2026-11-02）

版本**2.0.9+45**，源码`6fdd581802239e9a87eaf50669f43afdeb1f3cf6`，SQLite20，后台0004不变。Windows/Android已核验；相关回归80项通过、静态检查无问题，未重跑整套客户端。源码及最终文档均提交推送2.0分支，原签名和书籍配置不变，真机仍需验收。

[交付和下载](../release/fly_2_0_9_build45.md)、[备案和哈希](apk/20261102-build45/README.md)。正式包/原测试升级包按现有签名选择，不能互相覆盖。dist包本体和私有配置不随Git。

---


## 历史 build44（2026-11-01）

版本 **2.0.8+44**，SQLite20、后台0004，源码 `404aea37047a01d24e29569fbbc2fb21a2995595`。Windows安装器/便携包、原正式签名和原测试签名APK、同源原生后台包已构建核验。客户端：全量运行417项通过、4项发现问题；修正后定向47项全部通过，421个不同用例均有通过记录；未再重复第二次全量；后台全量61项通过，静态检查无问题。

[交付与下载](../release/fly_2_0_8_build44.md)、[公开清单与正式备案字段](apk/20261101-build44/README.md)。正式包名`com.flyproduct.fly`、证书MD5`5E96E7B982BF8DB94FEF71F148BC0859`不变，原测试包证书MD5`D0A58DFC764BF184B0E641434E8B757F`不变。两个身份不能互相覆盖，按原安装身份选择；先保留完整备份，不用旧build42打开schema20目录。

全部公开工作区本地提交，未推送/部署；[Ubuntu原生部署](../../server/deploy/ubuntu-native.md)由用户执行，私有配置不随公开包。下面均为历史包记录，iOS仍无真实发布证书。

---


## 历史 build43（2026-11-01）

版本 **2.0.7+43**，SQLite schema20，源码提交 `55bd11da84281ae650648967490562660bdfe0fb`。Windows安装器/便携包、原正式签名APK、原测试签名APK及公开Ubuntu后台包均已构建核验；完整客户端 405 项、后台41项通过，静态检查无问题。下方 build42 为保留的历史记录。

[本轮交付与下载](../release/fly_2_0_7_build43.md)、[公开清单与备案字段](apk/20261101/README.md)。正式包名 `com.flyproduct.fly`、证书MD5 `5E96E7B982BF8DB94FEF71F148BC0859` 不变。测试包继续沿用原测试证书，不能与正式包互相覆盖；保持原签名、保留完整备份，不让旧 build42 打开 schema20 数据。

没有推送或部署，Ubuntu由用户按[详细文档](../../server/deploy/cloud_sync_20261101.md)自行操作，发件配置另行安全复制。

---

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
