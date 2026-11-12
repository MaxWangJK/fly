# build60 Android公开核验材料

Fly 2.0.24+60，源码`eab04c579145235585198f0cef015588ff604d31`，包名com.flyproduct.fly、版本代码60。
[清单](manifest-Fly-2.0.24-build60.json)、[备案](Fly-Android-Release-Filing-Info-build60.txt)、[原公钥](../20261016/Fly-Android-Release-Public-Key.txt)、[原证书](../20261016/Fly-Android-Release-Certificate.cer)。

原正式/原测试签名保持，非签名内容一致；三种ABI、非调试属性及16KB包对齐已验证。按现有安装身份选择覆盖升级，首次安装可选正式签名包。签名证书MD5与APK文件哈希不同。

本版减少大视频的反复同步校验和播放器重复刷新，并完善退出、报错与重试的暂停释放。43项不同的相关用例、静态检查、独立Windows原生播放与合成文件AOT验证通过；没有Android真机或Apple验收。[修复原因与证据](../../../release/video_performance_20261112.md)、[交付](../../../release/fly_2_0_24_build60.md)。私有配置和安装包不在Git。
