# build50 公开核验材料

Fly 2.0.14+50，源码`4293db91a9e2086c007e5bd32c9df3b931ff1bb9`，SQLite20、后台0004不变。
[清单](manifest-Fly-2.0.14-build50.json)、[备案字段](Fly-Android-Release-Filing-Info-build50.txt)、[原公钥](../20261016/Fly-Android-Release-Public-Key.txt)、[原证书](../20261016/Fly-Android-Release-Certificate.cer)。
两种原安卓签名保持，非签名内容一致；按已有安装身份选择正式包或原测试升级包。正式包名com.flyproduct.fly，版本代码50。Windows安装器未作发行代码签名。
相关回归171项通过、0项跳过，新增输入用例13项通过；应用lib/test静态检查无问题。未重跑整个客户端、后台、实体设备或Apple构建。
[交付](../../../release/input_continuity_20261107.md)。安装包、原私钥、私有配置和真实数据均不在Git中。
