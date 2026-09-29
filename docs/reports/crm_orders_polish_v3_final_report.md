# Fly CRM / Orders Polish V3 — Final Report

完成日期：2026-09-02  
项目：`E:\workSpace\fly`  
目标：标签生命周期、排序、删除交互、默认启动位置、日历滚轮与 CRM / Orders 视觉统一。

## 完成结果

### 标签生命周期

- 建立统一 `TagCleanupService`，集中判断引用、保护状态与可删除性。
- 普通标签在 Customer / Order 零引用后从 `tags` 表物理清理。
- Customer Category 关联标签和仍被 Task 使用的标签受到保护。
- 应用启动执行一次安全的历史孤儿标签修复。
- Customer Filter Tag 仅在 Hover 时显示红色删除按钮。
- 删除被引用标签前显示客户与订单的精确引用数量；确认后事务化删除两类 links 和 tag。

### Customer

- 基本信息默认展开且仍可折叠。
- 下次跟进与重复规则使用相同高度、边框、圆角与字阶。
- 新增领域值 `every2Months`，按日历月计算并执行月末 clamp。
- 列表搜索框统一为 36px；筛选标签改为低饱和扁平样式。
- 优先级背景减淡；选中行使用轻背景和 2px 指示线。
- 备注与跟进记录改用共享扁平详情入口。
- 客户行支持右键软删除；有关联订单时确认框显示订单数量且不删除订单。

### Orders

- Sidebar 最多显示 8 个订单标签，不提供“更多”。
- 标签按有效订单引用数降序排列，同数量按创建顺序稳定排序。
- 默认严格排序：紧急重要、紧急、高、中、重要、低；同 rank 按 `createdAt DESC`。
- 紧急与重要显示为两个独立的低饱和 Capsule Badge。
- 列表搜索框、行高、优先级背景与选中态和 Customer / Tasks 对齐。
- 订单详情、财务信息、订单备注统一使用共享 `DetailSectionEntry`。
- 订单行支持统一右键菜单、确认与软删除。

### Tasks / Calendar / Matrix / Startup

- Calendar Task 与 Matrix Task 复用 `TaskDeleteAction`，右键确认后软删除。
- Customer / Order / Task 的危险操作菜单复用统一视觉与确认组件。
- 新安装或无恢复状态时默认进入 `客户 → 今天`。
- Calendar 支持鼠标滚轮向前、向后切换月份。

## 自动化验证

- `flutter analyze`：PASS，0 issues。
- `flutter test`：PASS，57 tests。
- `flutter build windows --release`：PASS。
- V3 新增覆盖：
  - 孤儿标签启动修复与 Category 保护
  - Customer / Order 跨引用清理
  - 被引用标签事务化删除
  - 两月 recurrence 与跨年、闰年月末 clamp
  - Order Tag Max 8 与引用排序
  - Order Rank 严格顺序与同组新单优先
  - Customer / Order / Calendar / Matrix 右键软删除
  - 默认 Customer Today 启动
  - Calendar 鼠标滚轮切月

## Windows Release

- 可执行目录：`build\windows\x64\runner\Release`
- 交付包：`dist\Fly-CRM-Orders-Polish-V3-windows-x64.zip`
- 包大小：14,555,255 bytes
- SHA-256：`BAEDC49329DDAA649FF3F9C872AFC19976AB5AE84934CAC44B56D3D96EA2D55C`
- 压缩包已核验包含 `fly.exe`、Flutter runtime、SQLite、plugins 与完整 `data` 目录。
- 正式版通过 `flutter run -d windows --release` 启动。
- 最终运行进程：PID `15912`，状态 `Responding = True`；运行会话保持连接，未发送退出指令。

## 视觉验收

- UI Review：[ui_review.md](../design/polish_v3/ui_review.md)
- 九个评分维度全部不低于 8。
- 截图目录：`docs/screenshots/polish_v3/`
- 必备截图：
  - `customers_today.png`
  - `customer_detail.png`
  - `orders_all.png`
  - `order_detail.png`
  - `order_priority_flags.png`
  - `customer_context_menu.png`
  - `order_context_menu.png`

## 最终判断

- Fly 打开后立即进入今天需要联系的客户。
- Customer / Orders 与 Tasks / Calendar / Matrix 使用同一套产品语言。
- CRM / Orders 已显著降低后台系统与 ERP 感。
- 紧急重要订单、无用标签、右键删除影响范围均可快速识别。
- 详情保持紧凑，并通过 Extension Panel 保留渐进展开能力。
