# Fly 1.0.0+24 候选构建记录

## 本次改动

- 新安装用户默认隐藏 Dashboard，仍可在设置中开启；已有用户保存的导航偏好不覆盖。
- 客户、订单列表进入时自动选中当前可见的第一条并展示详情；空列表保留空状态。
- 今日复盘点击“前一天”时优先定位更早的最近一条记录；没有更早记录则进入前一个自然日。
- 全局搜索和客户、订单、任务、笔记、文件等搜索统一支持模糊匹配，并保留中文片段与多词查询。

## 自动检查

- `flutter analyze`：零问题。
- `flutter test`：212 项通过。
- `flutter build windows --release`：成功。
- `scripts/build_installer.ps1`：成功，安装包 `dist/Fly-Setup-1.0.0-build24.exe`。
- SHA256：`A9C7B809FF647AF1E0B8B00264E55ACF37AFECF5BF992F93933390E704E94543`。

## 正式销售前仍需完成

- 在真实 Windows 用户环境进行安装、升级、数据迁移与核心流程人工验收。
- 安装包当前未做 Authenticode 签名。
- 本次打包工具输出含 `Non-commercial use only` 标记；发布者需确认并解决商业发行授权安排。

本构建为候选测试包，不标记为正式可售发行。
