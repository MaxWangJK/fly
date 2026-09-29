# Fly Polish V8 验收报告

日期：2026-09-08

## 已完成

- Today 与 Dashboard 共用本地日历日区间查询；跨天、单端日期、完成状态和删除状态按 V8 规则处理。
- 四象限显示创建时间：11px 次要文字，第二行右侧，保留原有完成样式与拖动交互。
- 设置重构为八类设置中心，200px 分类栏、740px 最大内容宽度；支持深色与窄窗口分类选择器。
- Dashboard 单独显隐；客户与订单联动显隐；持久化到现有 AppSettings，业务数据不删除。
- 启动等待配置后，按 Dashboard → 客户今天 → 任务今天选择入口；隐藏当前工作区或访问隐藏路由时自动回退。
- 保留客户 Excel 导入、Excel 导出、提醒、备份恢复和数据目录迁移入口。未新增其他业务模块。

## 验证结果

| 项目 | 结果 |
|---|---|
| Flutter analyze | PASS，0 issues |
| Flutter test | PASS，162 项 |
| V8 UI / 截图复验 | PASS，5 项 |
| Windows Release build | PASS |
| Windows 安装包 | PASS |
| Flutter run Windows release | 已启动已构建的正式版，保留运行 |

运行使用 `flutter run -d windows --release --use-application-binary=E:/workSpace/fly/build/windows/x64/runner/Release/fly.exe`，直接验证与安装包相同的已构建二进制，避免再次编译改变产物。

安装包：`dist/Fly-Setup-1.0.0.exe`。

SHA256：`0F0B2D605E3609926599B59BCE1B85790B8F518228B60BF16BAE418BEF0B45C2`。

安装包未签名，Windows 可能显示未知发布者；调试符号未包含在安装包中。

## 截图

- `docs/screenshots/polish_v8/settings_navigation.png`
- `docs/screenshots/polish_v8/settings_dark.png`
- `docs/screenshots/polish_v8/settings_narrow.png`
- `docs/screenshots/polish_v8/matrix_created_time.png`

截图来自真实 Flutter 界面与独立内存测试数据库，不使用用户真实业务数据。

## 建议人工验收

1. 设置一个昨天开始、明天截止的任务，确认它出现在今天任务和 Dashboard 中；完成后两个位置均移除。
2. 在设置中关闭 Dashboard，应跳到客户今天；再关闭客户与订单，应跳到任务今天。
3. 重新打开开关，确认客户与订单数据仍在；关闭应用再启动，确认显隐与默认入口保存。
4. 在四象限查看创建时间，并尝试拖动任务，确认原交互保持。

本轮不修改数据库结构，不删除用户记录，不重做日历或装柜模拟。按 V8 范围完成后停止扩展。
