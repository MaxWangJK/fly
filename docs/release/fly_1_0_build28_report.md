# Fly 1.0.0+28 构建记录（2026-10-04）

## 本次调整

- 今日复盘历史卡片改为按实际内容自适应高度；空字段不占位，长答案自然换行。
- 固定提问在卡片中缩成左侧短标签，完整问句可悬停查看；分组以所选主题的柔和色块区分。
- 无数据库迁移、新增依赖或用户数据重建。

## 验证与产物

- `dart format`：本次修改的 Dart 文件已格式化。
- `flutter analyze --no-pub`：零问题。
- `flutter test --no-pub`：219 项通过；备份和旧组件测试仍有既有的 Drift 调试提示，但未造成测试失败。
- 已查看历史卡片在默认浅色双列和清朗商务深色下的测试渲染；截图位于 Git 忽略的 `artifacts/`。
- 同一次 `scripts/build_installer.ps1` 流程重新构建 Windows x64 Release 和安装器。应用内版本标记为 `1.0.0+28`，离线授权已启用。
- 安装器：`dist/Fly-Setup-1.0.0-build28.exe`（12,530,527 字节）。
- SHA256：`F4C6B606223FE92E5E74C8C74A9EC7B0FF2DF2BC689DB61F3D485470C5788118`；独立计算结果与 `dist/Fly-Setup-1.0.0-build28.sha256.txt` 一致。

## 对外出售前的剩余门槛

这是**未签名的最终功能候选包**，不是已验证的正式可售发行。尚未在干净 Windows 环境验证安装、旧版升级、激活、卸载保留 FlyData 与真实旧库备份恢复；发布者还需确认收费授权、隐私与第三方许可、代码签名，以及 Inno Setup 7 的商用授权。当前编译器明确输出 `Non-commercial use only`。详见 [fly_1_0_release_plan.md](fly_1_0_release_plan.md)。
