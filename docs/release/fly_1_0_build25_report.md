# Fly 1.0.0+25 — 清朗商务配色候选包

## 交付

- 新增可选的「清朗商务」主题；旧主题与用户已有选择不变。
- 在该主题下，Dashboard 使用紧凑指标、真实待处理数量对比和明细卡片；不使用虚构趋势。
- 文件图标视图与笔记列表、编辑区采用更清楚的灰白分层和轻边框。
- 外观设置增加配色预览，切换即时生效并持久保存。
- 设计原则和色值见 `docs/design/clarity_business_palette.md`。

## 自动检查与视觉复核

- `flutter analyze --no-pub`：零问题。
- `flutter test --no-pub`：214 项通过。
- 隔离示例数据截图：`artifacts/clarity/dashboard.png`、`artifacts/clarity/files.png`、`artifacts/clarity/notes.png`。三个页面均已人工查看，无溢出。
- Windows Release 与安装器编译成功，版本标记 `1.0.0+25`。
- 安装包：`dist/Fly-Setup-1.0.0-build25.exe`，SHA256：`B817836A8EC6743BEB8ADC441AF5E74A2432306EA7254AF05C90C4012BC8B761`。

## 尚未完成的发布事项

- 未在真实用户数据目录安装或进行手动验收。
- 安装包未做 Authenticode 签名。
- Inno Setup 编译器显示 `Non-commercial use only`。正式销售前需由发布者确认打包工具的商业使用安排。

因此 build 25 是体验新主题的测试包，不标记为正式可售发行。
