# build46 公开核验材料

Fly 2.0.10+46，源码`2d0c95ff7b81d3cb73b817a4858b657602ebf993`，SQLite20、后台0004不变。
[公开清单](manifest-Fly-2.0.10-build46.json)、[备案字段](Fly-Android-Release-Filing-Info-build46.txt)、[原公钥](../20261016/Fly-Android-Release-Public-Key.txt)、[原证书](../20261016/Fly-Android-Release-Certificate.cer)。
两种原安卓签名保持、非签名内容一致。正式包与原测试版按现有安装身份升级，不能混用覆盖。Windows安装器未作发行代码签名。Git只保存公开材料，安装包在忽略的dist。
本轮相关回归47项通过、1项按测试开关跳过，静态检查无问题，未重复整套客户端或后台测试，未进行真机、Apple和生产部署验收。[交付说明](../../../release/fly_2_0_10_build46.md)。
