# Fly 3D 装柜模拟 V1 最终报告

日期：2026-09-06

## 完成范围

- 一级“工具”导航、工具二级栏和“装柜模拟”工作区。
- 40HQ、20GP 内置箱型，可编辑最大载重与安全间隙；尺寸计算统一使用整数毫米，重量统一使用整数克。
- 可复用货物库、cm/mm/m 输入、数量与重量设置、旋转限制、堆叠属性和柔和颜色。
- Single-SKU Grid Packing：遍历允许方向，同时受空间、载重、数量与间隙约束。
- Multi-SKU 启发式装载：重货优先、规则分层、AABB 边界与碰撞约束。
- 交互式 3D 场景：透明显柜、网格、分节、Orbit、Zoom、Pan、选择、拖动、表面吸附、网格吸附、90°旋转、复制、删除、重置、撤销与重做。
- 方案保存与重新打开；数据库只保存 Domain 数据和毫米坐标，不保存渲染对象。
- 装载 Summary、空间/重量利用率、剩余空间、前后半段重量分布、安全提示、复制摘要与 PNG 截图导出。
- Drift Schema 9 增量迁移，保留原有客户、订单、任务、日历、四象限及其它已有数据。

## 标准算例

40HQ：11900 × 2200 × 2690 mm，最大载重 28000 kg。

WPC 格栅：2900 × 160 × 120 mm，18 kg/包。

- 宽度：13 排。
- 高度：22 层。
- 长度：4 节。
- 单节：286 包。
- 理论空间最大：1144 包。
- 1144 包总重量：20592 kg，未超过默认载重。
- 数量 284 时实际装入 284 包，并保留 2 个空位。

## 数据与算法验证

- 40HQ/WPC 精确结果 13 × 22 × 4 = 1144。
- 286、284、重量上限 280、方向优化、20GP、安全间隙均有单元测试。
- overlap、touch edge、outside、inside 均有 AABB 测试。
- 手动拖动的合法落点、非法回退、旋转、Undo/Redo 均有控制器测试。
- 方案创建、坐标保存、重新加载一致性已验证。
- Schema 8 → 9 迁移测试确认旧 Customer 数据保留，并正确初始化箱型和货物库。
- 1000+ 包装采用 Group Bounding Box + 批量网格线渲染，不创建 1144 个复杂 Widget；碰撞使用组级 AABB。

## 自动化验收

- `flutter analyze`：PASS，0 issues。
- `flutter test`：PASS，119 tests。
- `git diff --check`：PASS（仅提示 Windows 行尾转换，无空白错误）。
- `flutter build windows --release`：PASS。
- `flutter run -d windows --release`：PASS，Impeller OpenGLES 渲染后端正常。
- Release 进程：PID 1280，Responding = True，并保持运行供测试。

## 发布产物

- Release：`build/windows/x64/runner/Release/`
- 安装包：`dist/Fly-Setup-1.0.0.exe`
- 安装包大小：12,687,954 bytes
- SHA-256：`D4C921DEBF90879D2C9852B4CB290D84D9970528C8E31AFEA0C4CE8CDA225A1B`
- 校验文件：`dist/Fly-Setup-1.0.0.sha256.txt`

## 截图

- `docs/screenshots/container_loading/tool_workspace.png`
- `docs/screenshots/container_loading/40hq_empty.png`
- `docs/screenshots/container_loading/wpc_286.png`
- `docs/screenshots/container_loading/wpc_1144.png`
- `docs/screenshots/container_loading/mixed_cargo.png`
- `docs/screenshots/container_loading/manual_drag.png`

## 最终产品判断

1. 输入包装尺寸后，可立即看到横向、纵向、长度方向与理论最大数量：是。
2. 可清晰看到 13 排 × 22 层 × 4 节：是。
3. 286 包可作为一个 Cargo Group 放入并拖动第一节：是。
4. 不同货物可通过低饱和颜色区分：是。
5. 托盘可移动、90°旋转和删除：是。
6. 自动装载不会超过空间与重量约束：是。
7. 1000+ 包装使用批量分组渲染并保持可交互：是。
8. 方案可保存并再次打开，位置与旋转保持一致：是。
9. 当前场景可导出 PNG，直接发送给客户、工厂或装柜人员：是。

算法结果仅供装柜规划参考；实际装柜仍需结合箱门尺寸、包装变形、绑扎与操作间隙、箱体结构及当地重量规定确认。
