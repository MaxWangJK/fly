# Fly Container Loading Planner V2 验收报告
日期：2026-09-06

后续容量、未装确认、保存入口与鼠标交互修复见 [V2 Bugfix 报告](container_loading_v2_bugfix_report.md)。下文为初始 V2 验收记录，发布包和运行记录以新报告为准。

## 本轮完成

装柜工作流改为 Container → Sections → SectionCargoEntry → 本节自动装柜 → 3D 调整 → 保存整个方案。保留现有场景引擎、集装箱绘制、Fly 多栏布局和旧数据。

- 侧栏直接选择、编辑和新增箱型；内置 40HQ/20GP 可恢复默认。
- 40HQ 默认 4×2900 mm，末尾保留 300 mm 未分配区域；20GP 默认 2×2900 mm。
- 自定义分节长度校验；每节独立货物、数量、方向、左右位置、底部和堆叠设置。
- 货物库支持拖入分节、每节默认数量、规格编辑/复制、八色低饱和颜色和软删除。
- 已存方案默认最近五条，可展开全部、打开、编辑、重命名和确认删除。
- 分节混装支持托盘靠边/居中、垂直叠放、合法支撑面顶部以及侧面自由空间填充。
- 门扇立放映射为 X=门宽、Y=厚度、Z=门高，2000×800×43 mm 在 800 mm 节内可装 51 扇。
- 数量超过理论容量可一次确认覆盖；保存用户设置数量和覆盖标志，重复计算不自动改回。
- 3D 全部六个面参与可见性选择，修复反面无色；按相机深度排序并以可见面拾取。
- 100 包按真实完整层和余量绘制，不再占据 286 包的整节高度。
- 分节边界和标签、货物固定图例、托盘底边、选中组高度调整、90°旋转、组级碰撞及 Undo/Redo。
- 单一“保存方案”入口、PNG 场景截图导出、复制结果。

## 数据安全与兼容

Drift Schema 9 → 10 增量迁移：新增 container_sections 和 section_cargo_entries，旧方案自动建立默认节。旧组根据 X 区间关联分节；不完整属于某节的组归到第一节并 needsReview=true，原位置/旋转/数量仍保留。

SectionCargoEntry 保存货物规格快照，因此库编辑或软删除不会重写旧方案。保存整个 Plan 使用事务，覆盖 Section/Entry/Group 的过程失败会回滚。删除 Plan 不删除货物库或箱型。

## 场景验收

| 场景 | 结果与证据 |
| --- | --- |
| A：WPC 286/节 | 拖入第1节预填 286，自动装柜得到 13排×22层；UI 拖放测试通过 |
| 少量 WPC | 数量100仅占8层，最后一层9包；284按实际数量显示 |
| B：居中双托盘+WPC | 托盘 Y=500，两层总高2000；较小WPC填充左右和合法顶部空间 |
| C：托盘靠左 | Y=0，右侧约1000 mm空间可填充；禁止堆叠时顶部不放货 |
| D：门扇立放 | 800×2193×2000 mm货物组，共51扇，3D显示竖直薄板 |
| E：保存后恢复 | Sections、Entry数量/覆盖标志、货物快照和3D位置持久化测试通过 |
| 边界 | 自动装柜和手动Drop遵守箱体及所属Section边界；非法Drop回退 |
| 原有业务 | 客户、订单、任务、日历、四象限及V7功能全量回归通过 |

## 验证结果

- flutter analyze：PASS，0 issues。
- flutter test：PASS，132 tests。
- 全量日志：artifacts/container-loading-v2-tests.log。
- 场景绘制/截图专项：PASS，2 tests；另有侧栏拖放、最近五条、覆盖交互等Widget测试。
- flutter run -d windows --release：PASS，Impeller OpenGLES启动，进程响应正常。
- 发布构建与最终成品进程：见下方发布记录。

## 发布记录

- flutter build windows --release --obfuscate --split-debug-info=...：PASS。
- 安装包：dist/Fly-Setup-1.0.0.exe，12,107,918 bytes。
- SHA-256：F94EECCCE0BEEB4C94B83512CC497245063E6D2FAD389563E749755656010C78。
- 校验文件：dist/Fly-Setup-1.0.0.sha256.txt。
- Release 目录：build/windows/x64/runner/Release/。
- 最终成品独立启动：PID 6640，窗口标题 Fly，Responding=True，保持运行供用户测试。

## 截图

以下为自动化场景与界面验收截图；真实 Windows Release 启动单独验证。

- docs/screenshots/container_loading_v2/40hq_sections.png
- docs/screenshots/container_loading_v2/wpc_286.png
- docs/screenshots/container_loading_v2/wpc_100_actual_height.png
- docs/screenshots/container_loading_v2/wpc_1144.png
- docs/screenshots/container_loading_v2/pallet_center_stack_mixed.png
- docs/screenshots/container_loading_v2/pallet_left_mixed.png
- docs/screenshots/container_loading_v2/manual_adjustment.png
- docs/screenshots/container_loading_v2/door_51_upright.png

## 算法边界

“用户覆盖理论容量”保留的是业务设置数量。按准确尺寸无法摆放的部分单列为未装/待人工确认，不通过缩放包装或重叠箱体伪造空间成立。载重和碰撞约束继续参与计算。

混装为本地确定性启发式，不承诺数学最优。顶部货物必须满足支撑面尺寸；例如2900 mm长包装不会被自动强放到2800 mm长托盘的支撑面上。没有把分组批量渲染等同于已实测固定60 FPS。

本轮没有新增其它工具、网络装柜服务或第三方模型/算法依赖。
