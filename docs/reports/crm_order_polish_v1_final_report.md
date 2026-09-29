# Fly CRM / Order 微调 V1 最终报告

日期：2026-09-02

## 交付结果

本轮只对 CRM / Orders 做细化，没有重做或破坏任务、日历、四象限模块，也没有改变 Customer、Order、Task 的领域边界。

已完成：

- Customer 与 Order 共用统一优先级模型：低 / 中 / 高。
- 优先级统一使用“方块 + 对号”的单选交互，客户和订单列表均使用柔和、低饱和背景提示。
- 客户重复跟进简化为：从不、三天、每周、两周、每月。
- 重复日期以现有下次跟进日为基准；缺失时以今天为基准；月度规则支持月末与闰年。
- 客户详情重新压缩为高频信息优先的两列布局，客户来源提升到默认展开区域。
- 客户备注拆分为独立数据实体，支持新增、搜索、编辑、软删除、颜色块、最近备注预览和右侧扩展面板。
- 跟进记录支持最近记录预览、搜索、渠道选择、单输入框快速记录和右侧扩展面板。
- 窄窗口中扩展面板覆盖客户详情，不挤压主导航、二级导航和客户列表；宽窗口中固定在最右侧。
- 客户详情可直接新建当前客户订单，并自动跳转到订单详情；Customer 与 Order 双向导航保持有效。
- 订单高优先级、重要、紧急、生产中但工厂未下单等状态保持清晰的小面积视觉提示。

## 数据与迁移

- Drift schemaVersion：3。
- 新增 `customer_notes`，备注使用独立记录、排序、版本和软删除字段。
- v1 → v2 → v3 均通过增量迁移，不删除数据库。
- 旧 `customers.notes` 内容会迁移为第一条客户备注，同时保留原字段，避免数据损失。
- 旧 `none` 优先级迁移为低优先级。
- 旧 daily / weekdays / custom 跟进规则兼容映射为“三天”。
- 任务、日历、四象限以及既有 CRM / Order 数据均保留。

## 验证结果

- `flutter analyze`：通过，0 个问题。
- `flutter test`：35 / 35 通过。
- `flutter build windows --release`：通过。
- 关键覆盖：数据库迁移、备注迁移、月末/闰年重复规则、今日跟进、客户与订单双向导航、客户直接新建订单、最新备注/跟进预览、共享优先级、利润、收款、未下工厂警告以及既有任务/日历 UI。

## 验收截图

- `customer_detail.png`
- `customer_priority_high.png`
- `customer_notes_preview.png`
- `customer_notes_extension.png`
- `customer_followup_extension.png`
- `order_priority.png`

截图目录：`docs/screenshots/crm_polish/`

## Windows 交付

- Release：`build/windows/x64/runner/Release/fly.exe`
- 压缩包：`dist/Fly-CRM-Order-Polish-V1-windows-x64.zip`
- 压缩包大小：14,481,497 bytes
- SHA-256：`D3ED2604C4F029E4784CA54A99BF2A1B8A8780BA8A0F8BA9C875EA6C408050D4`
- 最终运行进程：PID 13936
- 运行状态：Responding = True；已保持窗口运行，供人工验收。

## 产品判断

CRM 详情现在优先回答“客户当前阶段、下次何时跟进、最新备注、上次沟通与下一步是什么”；Order 详情继续优先回答“订单到哪一步、是否漏下工厂单、利润和未收金额”。信息层级保持 Fly 的简洁生产力软件风格，没有扩张为传统 ERP 后台。
