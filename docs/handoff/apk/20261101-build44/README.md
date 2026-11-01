# build44 公开核验资料

Fly 2.0.8+44；源码 `404aea37047a01d24e29569fbbc2fb21a2995595`，SQLite20、后台0004。

[机器可读清单](manifest-Fly-2.0.8-build44.json)、[正式备案字段](Fly-Android-Release-Filing-Info-build44.txt)、[原正式公钥](../20261016/Fly-Android-Release-Public-Key.txt)、[原公开证书](../20261016/Fly-Android-Release-Certificate.cer)。

正式包与原测试签名包的非签名内容相同，身份各自保持原样；证书MD5不是APK文件哈希，不能互相覆盖升级。Windows安装器未作发行代码签名。包本体在忽略的 `dist/`，不随 Git 发布。

客户端：全量运行417项通过、4项发现问题；修正后定向47项全部通过，421个不同用例均有通过记录；未再重复第二次全量。后台全量61项通过，静态检查无问题。未实际部署/发件/真机/Apple验收。完整说明见 [交付记录](../../../release/fly_2_0_8_build44.md)。
