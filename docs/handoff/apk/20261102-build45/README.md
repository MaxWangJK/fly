# build45 公开核验材料

Fly 2.0.9+45；源码`6fdd581802239e9a87eaf50669f43afdeb1f3cf6`，SQLite20，后台0004兼容，本轮不改后台。
[公开清单](manifest-Fly-2.0.9-build45.json)、[备案字段](Fly-Android-Release-Filing-Info-build45.txt)、[原公钥](../20261016/Fly-Android-Release-Public-Key.txt)、[原证书](../20261016/Fly-Android-Release-Certificate.cer)。
正式与原测试包的非签名内容一致、签名身份不变，按原安装身份升级，不可混用覆盖。Windows安装器未作发行代码签名。安装包在忽略的dist中，Git只保存公开材料。
本轮相关回归80项通过，静态检查无问题，未重复整套客户端或后台测试，未进行真机/Apple/生产部署验收。详见[交付](../../../release/fly_2_0_9_build45.md)。
