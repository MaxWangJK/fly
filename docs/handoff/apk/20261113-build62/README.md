# build62 Android公开核验材料

Fly 2.0.26+62，源码`62d922c154cc0a4e04fa94532cc1678fef769f48`，包名com.flyproduct.fly、版本代码62。
[清单](manifest-Fly-2.0.26-build62.json)、[备案](Fly-Android-Release-Filing-Info-build62.txt)、[原公钥](../20261016/Fly-Android-Release-Public-Key.txt)、[原证书](../20261016/Fly-Android-Release-Certificate.cer)。

本版包含客户导入确认后自动创建或复用级别/状态，以及新建客户中状态新增、改名、停用和历史名称保留。电脑和手机均需更新以一致处理自定义状态。原正式/原测试证书身份保持，按已有身份覆盖升级；首次安装可用正式签名版。两包非签名内容一致，三种ABI、非调试属性和16KB包对齐已核验。备案证书MD5与APK文件哈希不同。

48项不同的相关用例和全项目静态检查通过；最终界面重复复验6项，提交源码后重复复验12项关键用例，重复部分不另计。没有物理手机、独立Win10设备或Apple验收。私有配置和安装包不在Git。[实现](../../../release/customer_status_custom_20261113.md) / [交付](../../../release/fly_2_0_26_build62.md)。
