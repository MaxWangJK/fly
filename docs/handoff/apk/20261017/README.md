# 安卓 build 41 公开构建记录

2026-10-17；源码 2.0.5+41、schema 19，原提交 24afa8d 后的工作区改动。

- [构建、版本、签名和哈希](manifest-Fly-2.0.5-build41.json)
- [可复制备案信息](Fly-Android-Release-Filing-Info.txt)
- [沿用的完整公钥](../20261016/Fly-Android-Release-Public-Key.txt)、[DER 公有证书](../20261016/Fly-Android-Release-Certificate.cer)、[PEM 公有证书](../20261016/Fly-Android-Release-Certificate.pem)

APK 本体在工程 dist，被 Git 忽略；公开材料没有私钥。两个 APK 功能相同，签名分别适配正式版和原测试版；不能互相覆盖。现成 Windows 包仍为 build 40。详情见 [APK 台账](../../APK_RELEASES.md) 和 [本轮报告](../../../release/fly_2_0_5_build41.md)。

## 后续 build 42

[2.0.6 构建清单](manifest-Fly-2.0.6-build42.json)、[当前备案字段](Fly-Android-Release-Filing-Info-build42.txt)、[修复记录](../../../release/fly_2_0_6_build42.md)。Windows 和 Android 均已重建；原 build 41 材料保留。
