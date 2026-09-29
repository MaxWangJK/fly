# Fly CRM / Orders Polish V3 — UI Review

评审日期：2026-09-02  
评审范围：Customer Sidebar、Customer List、Customer Detail、Order Sidebar、Order List、Order Detail、右键删除菜单。  
评审方式：Windows 桌面实机运行，使用独立验收数据库与 1264 × 681 窗口截图复核。

## 评分

| 维度 | 评分 | 结论 |
| --- | ---: | --- |
| Visual consistency | 9.2 / 10 | 客户、订单与任务模块沿用同一 Rail、Sidebar、List、Detail 结构；选中、悬停和图标语言一致。 |
| Information density | 9.0 / 10 | 客户行 48px、订单行 54px；主要字段可横向扫读，状态与标记保持次要层级。 |
| Flatness | 9.1 / 10 | 备注、跟进、订单详情、财务与订单备注统一为扁平入口，以间距和分隔线替代卡片套卡片。 |
| Typography | 8.8 / 10 | Workspace、详情标题、正文和 metadata 采用一致字阶，紧急/重要徽标为 12px Semibold。 |
| Spacing | 9.0 / 10 | Sidebar 38px 行高、36px 搜索框、列表与详情间距均遵循 Fly spacing tokens。 |
| CRM usability | 9.1 / 10 | 启动即进入“客户 → 今天”；客户阶段、下次跟进、重复、备注、跟进和订单在首屏可读。 |
| Order usability | 9.2 / 10 | 紧急重要订单置顶；状态、客户、日期和徽标一眼可辨，财务与生产详情保持渐进展开。 |
| Destructive action safety | 9.3 / 10 | 右键入口统一、危险色明确、执行前确认；删除客户会明确告知关联订单数量且只做软删除。 |
| Tag usability | 8.9 / 10 | 筛选标签低饱和、最多两行；删除按钮仅 Hover 出现，被引用标签会显示精确引用数量。 |

所有评分均不低于 8，达到本轮验收门槛。

## 本轮视觉决策

- 搜索框统一为 36px，搜索图标和 placeholder 降低视觉权重。
- Customer / Order 选中行取消整圈边框，改为轻背景与 2px 细指示线。
- High / Medium 优先级背景进一步降低饱和度；Low 保持接近普通背景。
- Customer Notes、Customer Follow-ups、Order Details、Financial、Order Notes 共用 `DetailSectionEntry`。
- `DetailSectionEntry` 使用标题、预览、可选 metadata、Chevron 和单条分隔线；Hover/Focus 提供轻量反馈。
- 紧急与重要采用两个独立 Capsule Badge，避免合并文字降低扫描效率。
- Sidebar 与 Task Sidebar 对齐 38px 行高、圆角、选中背景、鼠标指针与图标尺寸。
- 删除菜单统一使用红色图标与文字，不加入无关操作。

## 实机截图复核

- [客户今日](../../screenshots/polish_v3/customers_today.png)
- [客户详情](../../screenshots/polish_v3/customer_detail.png)
- [全部订单](../../screenshots/polish_v3/orders_all.png)
- [订单详情](../../screenshots/polish_v3/order_detail.png)
- [订单优先级标记](../../screenshots/polish_v3/order_priority_flags.png)
- [客户右键菜单](../../screenshots/polish_v3/customer_context_menu.png)
- [订单右键菜单](../../screenshots/polish_v3/order_context_menu.png)

## 产品判断

1. 打开 Fly 后会直接看到今天需要联系的客户。
2. CRM / Orders 与 Tasks 使用同一套导航、列表、选中态、间距和排版规则。
3. Customer / Order 已减少表单框与嵌套卡片，不呈现传统后台或 ERP 的视觉负担。
4. 紧急且重要的订单位于最前，并由两个独立徽标明确标识。
5. 普通零引用标签会清理，类别与任务使用的受保护标签不会误删。
6. 右键删除符合桌面操作习惯，确认信息能说明影响范围。
7. 客户和订单详情首屏保持紧凑，同时保留渐进展开能力。
