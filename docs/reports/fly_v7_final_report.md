# Fly V7 最终报告

日期：2026-09-06

## 完成范围

- 财务汇率限制并按两位小数参与计算；已收、未收、成本 Summary 仅显示原始币种，预计利润继续统一为 RMB。
- 每日自动备份、7/30 天保留、手动备份、可选目录、PreRestore 安全包、ZIP/版本/SQLite 完整性校验及失败回滚。
- Ctrl+K 全局搜索客户、订单、任务、备注、跟进与下一步，支持分组、200 ms debounce、上下键、Enter 和 Esc。
- Windows 原生提醒覆盖 Task Reminder、Customer nextFollowUpDate 与 Order deliveryDate；支持到期、10 分钟、1 小时和 1 天，并通过 Delivery Log 去重。
- CRM Next Action Type + 自由文本，支持仅选择类型，列表显示低饱和 Capsule。
- 一级 Dashboard，仅包含今天需跟进客户、今天任务、待收款订单、紧急订单、本月利润五块 Query Projection。
- Excel 客户模板与六步导入流程：Sheet、字段映射、20 行预览、标准化重复检测、跳过/覆盖/新增及失败原因。
- Customer / Order / Payment 共用 Attachment Repository 与 `FlyData/attachments` 存储；客户详情支持点击上传、拖放、分类、系统打开与确认删除。
- Drift Schema 8 增量迁移保留旧数据，并把 `order_files` 投影到统一 `attachments`，不删除兼容表。

## 数据安全验证

- 真实备份恢复测试同时覆盖 Customer、Order、附件元数据和物理文件。
- 损坏 ZIP 在替换当前数据之前被拒绝；当前数据保持不变，Windows 文件句柄正常释放。
- 恢复先在临时目录解包和迁移，再通过回滚目录替换；跨盘复制失败会清理部分目标后回滚。
- Schema 7 → 8 测试确认客户、订单和旧订单文件均保留。

## 自动化验收

- `flutter analyze`：PASS，0 issues。
- `flutter test`：PASS，101 tests。
- `flutter build windows --release`：PASS。
- `flutter run -d windows --release`：PASS。
- 独立 Release 窗口：已启动、响应正常，并保持运行供测试。

专项测试覆盖：FX rounding、原始币种 Summary、成本 Summary、备份恢复、损坏备份、全局搜索、提醒一次性投递、Next Action Type、Dashboard 精确计数、Excel 预览状态、附件重启持久化与数据库迁移。

## 发布产物

- Release：`build/windows/x64/runner/Release/`
- 安装包：`dist/Fly-Setup-1.0.0.exe`
- 安装包大小：12,586,100 bytes
- SHA-256：`B6522A92600EED1F92BF25DFE6E97F93B845944491C45E76DE2ACFCCF50F3F79`
- 校验文件：`dist/Fly-Setup-1.0.0.sha256.txt`

安装包使用与 Windows 原生通知一致的 AppUserModelID：`Fly.Desktop.Productivity.1`。

## 视觉验收

- `docs/screenshots/v7/dashboard.png`
- `docs/screenshots/v7/global_search.png`

Dashboard 保持低饱和、扁平卡片、紧凑文字与五块信息上限；全局搜索保持桌面命令面板式交互，没有引入 ERP 大屏或独立搜索页面。
