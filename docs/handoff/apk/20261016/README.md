# 安卓公开备案材料归档

2026-10-16，从实际正式签名 APK 的已核验交付材料复制，保持原始字节。这里仅包含公钥、公开证书、备案字段及核验清单，随 Git 保存；不含私钥或密码。

- [Fly-Android-Release-Filing-Info.txt](Fly-Android-Release-Filing-Info.txt)：可复制的正式安卓备案字段和适用范围。
- [Fly-Android-Release-Public-Key.txt](Fly-Android-Release-Public-Key.txt)：完整 RSA 模数，整行复制。
- [Fly-Android-Release-Certificate.cer](Fly-Android-Release-Certificate.cer)、[PEM](Fly-Android-Release-Certificate.pem)：同一正式安卓公有证书。
- [manifest-Fly-Android-Release-20261016.json](manifest-Fly-Android-Release-20261016.json)：正式包签名、哈希与验证状态。
- [manifest-Fly-2.0.4-build40.json](manifest-Fly-2.0.4-build40.json)：原功能测试包的历史构建清单，保留当时基线/工作区事实。

APK 本体、Windows 包及 `.fly` 成品仍在工程 `dist/`，被 Git 忽略，需要另行复制；正式签名原件在私有目录，必须安全迁移。文件哈希和测试/正式签名区别见 [APK 台账](../../APK_RELEASES.md)。公开证书不能恢复私钥，安卓证书不能用于 iOS 备案。
