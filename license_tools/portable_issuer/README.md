# Fly 内部免安装授权工具

Windows 单文件图形工具，只输入机器码以及激活天数或永久选项，生成并复制 Fly v1 格式的 Ed25519 授权码。客户端算法与原公钥保持一致，不重新生成签发身份。用户说明见 [使用与迁移说明](../../docs/licenses/portable_issuer_20261017.md)。

## 内部构建

在可信 Windows 开发机保留原 `license_tools/private/issuer.pem`、`public_key.txt` 和 Python 构建环境后运行：

```powershell
& scripts/build_license_issuer.ps1
# 也可使用已下载的官方固定版本包，离线构建：
& scripts/build_license_issuer.ps1 -PackagePath <官方 nupkg 路径>
```

输出为忽略目录 `license_tools/private/portable/Fly-License-Issuer.exe`，同目录有文件哈希清单及第三方许可。构建会核对固定 SHA-512 和原公私钥匹配，缺失或不符时停止，不初始化新钥匙。工具使用 Windows .NET Framework 4.8，不需要目标机安装 Python 或另外准备 DLL。源码编译器为系统 Framework64 中的 C# 编译器。

**该 EXE 内含原授权签发身份，仅供所有者内部使用。** 单文件离线签发意味着持有工具的人拥有发码能力；不以混淆、压缩或窗口隐藏作为密钥保护。输出目录限制为本机当前用户、SYSTEM 和 Administrators 访问，跨电脑拷贝后需重新保管权限。不要放官网、普通 `dist`、客户安装包、公开仓库或用户备份中。

## 验证

```powershell
& license_tools/portable_issuer/tests/run_tests.ps1 -PackagePath <官方 nupkg 路径>
flutter test --no-pub test/portable_issuer_compatibility_test.dart
flutter analyze --no-pub
```

C# 测试验证期限边界、原公私钥匹配、错误机器码拒绝、随机 nonce，以及真实 WinForms 的生成、模式切换、旧结果清除和复制。剪贴板使用测试替身，不改用户剪贴板；隐藏的测试窗口结束即关闭。

跨语言测试夹具使用独立的一次性测试密钥，不是正式签发私钥，也不是实际 Windows MachineGuid。当前固定夹具在 `test/fixtures/portable_issuer_v1.json`；重新构建测试产生的新夹具在 `.buildlog/license-issuer-tests/compatibility.json`。如更新协议，核查后再更新固定夹具，运行真实 `LocalLicenseService` 验证。测试不访问注册表、DPAPI、真实业务目录或现有激活状态。

依赖固定为 [BouncyCastle.Cryptography 2.7.0](https://www.nuget.org/packages/BouncyCastle.Cryptography/2.7.0)，源码来自 [官方仓库](https://github.com/bcgit/bc-csharp/tree/release-2.7.0)。签名调用官方库，未自行实现 Ed25519。许可来自该官方包的 `LICENSE.md`，打包为内嵌资源并另附文本；SHA-512 固定在 `dependency.json`。
