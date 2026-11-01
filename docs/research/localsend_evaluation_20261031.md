# LocalSend 源码评估与 Fly 局域网同步决策

日期：2026-10-31。Fly 评估基线：`c40935ba5260ab9bfeabedfe0dc651124f2f0637`，分支 `codex/fly-2-sync`，源码 `2.0.6+42`、schema 19。

2026-11-01 续补：以下保留当时的只读评估。后续已在 Fly 原协议中开发下载续传、传输调度、已配对设备发现与三设备自动合并，没有集成 LocalSend，也没有实现 LAN TLS；当前实现和验证边界见 [本轮同步记录](../release/sync_multi_device_20261101.md)。

## 本轮要求与结论

用户要求确认电脑与手机当前如何同步文件，先研究 LocalSend 源码；确有必要时再将其二次开发并融入 Fly，没有必要则跳过。

**决策：本轮跳过 LocalSend 集成，保留 Fly 现有同步协议和功能代码。** LocalSend 同样使用局域网，不能把“局域网”和“LocalSend”视为两种互斥网络。它的设备发现、TLS 身份验证和传输处理值得借鉴，但通用文件收发会话不能直接替代 Fly 的业务增量同步。当前没有真实手机上的对照测速证据，不能承诺替换后更快。

本轮只新增研究记录、文档入口并澄清续传范围；没有导入第三方运行时、增加依赖、升级 SDK、改变配对格式、修改数据库或重新打包。以下改进优先级是建议，尚未实现，不是接续对话应自动执行的任务单。

## 实际研究的上游版本

没有仅依据介绍页或早期 Dart 实现作判断。读取了官方完整源码快照的相关模块，核对当前稳定版和主分支：

| 对象 | 固定版本 | 核对内容 |
| --- | --- | --- |
| [稳定版 v1.18.2](https://github.com/localsend/localsend/releases/tag/v1.18.2) | `af0416be50770a97760f7070684bc667b759a15c` | Flutter 调用链、Rust HTTP 客户端/服务端、上传会话、保存与校验、TLS、设备发现、失败重试、构建依赖与许可 |
| [主分支快照](https://github.com/localsend/localsend/tree/92e133aa43869e94d394fd04fa70c50a0f796a64) | `92e133aa43869e94d394fd04fa70c50a0f796a64` | 同一路径对照；额外连接总数/单 IP 限制等演进，不把开发分支能力写成稳定版承诺 |
| [公开协议 v2.2](https://github.com/localsend/protocol/blob/62bd3406ec80d62f2ed46269cdc06c4dcc391083/README.md) | `62bd3406ec80d62f2ed46269cdc06c4dcc391083` | 发现、注册、prepare-upload、文件令牌、upload、cancel、反向下载 |

研究缓存位于 Git 忽略的 `.buildlog/research/localsend-20261031/`，没有执行上游代码、下载二进制程序或把源码副本纳入 Fly。可迁移依据是上表固定提交链接。两个源码 ZIP 的 SHA-256 分别为：

- 稳定版：`89F26DADACEFCF4BC62AB652A02F10D61586C38082C6F7EF1AB45C83D0D19578`。
- 主分支：`144641BE1D9AD3C69351D12A4A65639523FAC112DE91D29C23E05D951BD1FFDD`。

## Fly 当前的真实链路

1. 电脑启动 `LanHostService`，默认在 TCP 8765 提供局域网 HTTP 接口。手机扫描电脑二维码，完成短期配对码验证，保存设备令牌和工作区身份；手机主动连接电脑，无须安装 LocalSend。
2. 客户、订单、任务、文件夹和附件记录通过 Fly 的 Outbox、稳定 ID、版本/游标、幂等处理和冲突机制同步。文件夹移动同步的是原记录的目录关系，不能简化成重新发送一份同名文件。
3. 实体内容通过同一电脑的 `/api/files/...` 接口上传/下载，按 SHA-256 识别内容。上传按最多 4 MiB 分片，服务端返回已有偏移，可以接续尚存的上传 `.part`；完成时检查长度与哈希。已有内容可避免重复上传整个文件。
4. 下载流式写入 `.part`，验证长度和 SHA-256 后更名到正式位置。**当前下载中断会清理 `.part`，下一周期从头下载；尚无 HTTP Range 下载续传。** 不应把“上传可续传”写成“双向均能按字节续传”。
5. 前台约每 2 秒检查一次增量，本机业务写入约 250 ms 合并触发。纯 LAN 没有常驻 WebSocket；隐藏的云端实现才使用 WebSocket 通知加 HTTP 拉取。WebSocket 是变更通知方式，不能单靠它提高文件字节传输速度。
6. 手机进入后台时停止同步并关闭连接，恢复前台重试已启用的连接；连续三次失败停止自动重试。电脑在开启服务且程序仍运行时监听。没有额外安装常驻系统服务。

局域网文件流量不经过官方云或用户自建公网服务器。此前的 6 Mbps 服务器出口不是这条路径的限速因素；两设备之间的 Wi-Fi、有线链路、磁盘、CPU 和防火墙才直接影响结果。仍需网络互通；不同 Wi-Fi 名称不必然不通，同一 Wi-Fi 也可能因访客隔离而不通。

本地证据：

- [局域网主机与文件接口](../../lib/features/sync/services/lan_host_service.dart)：`start`、`_handle`、`_files`。
- [二维码、客户端与生命周期](../../lib/features/sync/presentation/sync_controller.dart)：`pairingPayload`、`_startHost`、`_startLanClient`、`suspend`、`resume`。
- [同步调度](../../lib/features/sync/services/sync_engine.dart)：`start`、`_sync`。
- [文件协调与上传偏移](../../lib/features/sync/services/file_sync_service.dart)：`synchronize`、`_upload`。
- [HTTP 传输与下载](../../lib/features/sync/data/cloud_sync_transport.dart)：`LanSyncTransport` 复用 HTTP 实现；类名包含 Cloud 不代表 LAN 数据会绕行云端。

## LocalSend 源码中值得借鉴的实现

| 能力 | 上游实现与意义 | 对 Fly 的判断 |
| --- | --- | --- |
| 设备发现 | UDP 组播公告，默认 `224.0.0.167:53317`；HTTP 注册、已知地址和子网扫描作为补充 | 有助于电脑 IP 改变后的重新发现，但发现设备不等于授予业务工作区访问权；二维码仍应保留为信任入口 |
| 连接加密与身份 | 自签名证书、TLS 握手中的证书 SHA-256 指纹匹配、客户端证书及会话校验；局域网请求不跟随重定向 | Fly 当前 LAN 是 HTTP，设备令牌鉴权不等于链路加密；这是需要优先改善的具体差距，可以单独设计，无须更换业务协议 |
| 文件收发 | 先协商会话和每文件令牌，再流式 POST 上传；可取消并重试失败文件，协议允许不同文件并行 | 适合通用文件投递；还需另做与 Fly 的附件 ID、哈希、归属、方向和工作区绑定的桥接 |
| 校验与持久化 | Rust 接收端以流处理内容，可选 SHA-256 校验，按路径/Android 文件描述符等落盘 | 可借鉴背压、流式计算哈希和取消处理；不能照搬可选校验策略来弱化 Fly 已有的强制完整性检查 |
| 续传 | 审阅的 v2.2 文件上传 API 没有偏移协商字段，接收路径使用文件创建/截断；失败文件重试不等于从字节偏移继续 | 不能认为引入 LocalSend 就自动解决 Fly 的下载续传。该结论限于上述协议与代码路径，不概括所有未来版本或第三方实现 |
| 平台生命周期 | 上游有传输前台服务，使部分手机传输可在最小化后继续 | 与 Fly 已确认的“后台断开”要求不同，不能直接带入该行为 |
| 构建集成 | 稳定快照已采用 Rust 核心及 `flutter_rust_bridge`；应用还绑定其自身状态/路由和平台依赖 | 不是增加一个简单 Dart 包。抽取核心虽可行，仍增加各平台原生库、桥接、打包和回归工作；没有证据要求现在承担这些成本 |

关键上游源码入口（全部固定提交）：

- [Rust 客户端和流式上传](https://github.com/localsend/localsend/blob/af0416be50770a97760f7070684bc667b759a15c/packages/core/src/http/client/v2.rs)。
- [上传会话、文件令牌与接收端](https://github.com/localsend/localsend/blob/af0416be50770a97760f7070684bc667b759a15c/packages/core/src/http/server/v2.rs)。
- [接收文件、长度及哈希处理](https://github.com/localsend/localsend/blob/af0416be50770a97760f7070684bc667b759a15c/packages/core/src/http/server/common/save.rs)。
- [TLS 指纹验证](https://github.com/localsend/localsend/blob/af0416be50770a97760f7070684bc667b759a15c/packages/core/src/http/client/server_cert_verifier.rs)。
- [发现与回退](https://github.com/localsend/localsend/blob/af0416be50770a97760f7070684bc667b759a15c/packages/core/src/discovery/mod.rs)。
- [Flutter 上传桥接](https://github.com/localsend/localsend/blob/af0416be50770a97760f7070684bc667b759a15c/packages/localsend_isolates/lib/src/task/upload/http_upload.dart)、[失败重试及前台传输服务调用](https://github.com/localsend/localsend/blob/af0416be50770a97760f7070684bc667b759a15c/app/lib/provider/network/send_provider.dart)、[Rust 桥接依赖](https://github.com/localsend/localsend/blob/af0416be50770a97760f7070684bc667b759a15c/packages/localsend_isolates/rust/Cargo.toml)。
- [开发分支的连接限额](https://github.com/localsend/localsend/blob/92e133aa43869e94d394fd04fa70c50a0f796a64/packages/core/src/http/server/connection_limit.rs)。

上游项目根目录使用 [Apache-2.0](https://github.com/localsend/localsend/blob/af0416be50770a97760f7070684bc667b759a15c/LICENSE)。若未来复用源文件或库，应按该许可保留所需声明、标明修改，并逐项核对实际引入的依赖许可。本轮没有复制运行代码，因此没有新增第三方分发组件。

## 为什么暂不整合

LocalSend 已有自动接收和信任设备等便利功能，并非只能人工逐张确认。但“接收了一个文件”仍不能表明 Fly 已正确处理其客户归属、目录移动、离线编辑、删除墓碑或冲突版本。整体改成 LocalSend 会丢失这些语义；仅替换文件字节传输，则需要额外适配层，并保留现有元数据和冲突系统。

对现阶段的电脑加手机、约 20 MB 文件场景，未发现必须切换协议才能解决的问题。两者都走本地网络；Rust/流式传输可能改善 CPU 或处理开销，但实际提升取决于设备瓶颈。本轮没有运行 LocalSend、没有 Android/Windows 同网络 A/B 测速，不宣称 Fly 更快或 LocalSend 必然更快。

## 后续优化建议与重新评估条件

1. **优先保护局域网链路**：设计电脑持久 TLS 身份，二维码携带指纹，手机在发送令牌及内容之前固定校验；证书改变必须明确重新确认，不静默退回 HTTP，也不以接受所有证书作为完成方案。迁移要兼容现有配对和设备撤销。
2. **完善双向中断恢复**：增加受鉴权的 Range 下载、偏移/版本校验和可恢复临时文件；保留强制最终哈希校验。分别验证断网、后台中止、重启和源文件变化。
3. **减少等待和磁盘开销**：当前主机把请求放在同一队列，长下载可能延后业务请求；文件服务还会在周期中重复扫描、计算哈希和查询已有内容。先测量，再分离受限文件 I/O 与业务事务队列、缓存未变化文件的校验结果；不能为加速破坏上传串行性和版本一致性。
4. **改善重连与延迟**：在已配对设备范围内发现电脑新地址，失败仍能扫码；可考虑局域网事件通知配合游标补查。通知不携带业务事实、不替代重放和完整性校验，继续遵守手机后台断开与三次失败停止。

如果后续明确需要与独立 LocalSend 客户端互传，或实机压测证明传输核心而非无线网络/磁盘是主要瓶颈，再评估增加独立的通用收发适配器。外部收到的文件应走 Fly 现有导入流程；不能让普通 LocalSend 文件收发请求直接修改 Fly 业务记录。原同步协议应可继续使用，并有明确回退，不做无证据的整体重写。

## 本轮验证与边界

2026-10-31 使用原有 Flutter SDK、临时数据库和合成文件运行以下现有测试，**共 11 项通过**：

- [文件真实同步](../../test/fly_201_file_sync_test.dart)：含 20 MiB 文件双向传输、字节一致性和进度、旧 Windows 相对路径、目录移动/批量移动以及永久删除同步。
- [同步基础](../../test/sync_foundation_test.dart)：本地事务、版本/游标等基础约束、配对、幂等、单向权限及撤销。
- [状态详情](../../test/sync_status_details_test.dart)：待发送/下载、实体进度、最近成功等展示。

测试日志：忽略目录 `.buildlog/localsend-comparison-sync-tests-20261031.log`。测试输出包含已有 Drift 多数据库实例提示，最终无失败；没有为本轮研究修改测试或生产代码。

这些测试使用本机回环网络，不是两台真实设备的 Wi-Fi 测速，不验证路由器隔离、系统防火墙或手机厂商后台行为，也没有新增断网续传实测。没有重跑完整客户端测试、构建新安装包或执行 LocalSend 构建；原 build 42 发布证据日期不变。本轮文档修改没有自动提交或上传远端。
