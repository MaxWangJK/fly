# build61 Android公开核验材料

Fly 2.0.25+61，源码`ef10d479a0ab2bfb22d077025fa3cb4d3ff821bf`，包名com.flyproduct.fly、版本代码61。
[清单](manifest-Fly-2.0.25-build61.json)、[备案](Fly-Android-Release-Filing-Info-build61.txt)、[原公钥](../20261016/Fly-Android-Release-Public-Key.txt)、[原证书](../20261016/Fly-Android-Release-Certificate.cer)。

原正式/原测试证书身份保持，两个APK的非签名内容一致，三种ABI、非调试属性与16KB包对齐已核验。按原安装身份选择覆盖升级，首次安装可选正式签名包。备案证书MD5与APK文件哈希不同。

本版包含实体文件改名、局域网已有实体跟随改名和新建客户弹框修复。50项不同的相关回归及静态检查已在2026-11-12通过；2026-11-13对已提交源码重复复验12项关键用例通过，不重复算作62项。没有物理手机或Apple验收。[修复](../../../release/file_rename_customer_layout_20261112.md) / [交付](../../../release/fly_2_0_25_build61.md)。私有配置和安装包不在Git。
