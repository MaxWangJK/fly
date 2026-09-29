# 装柜模拟 V3 交付记录

日期：2026-09-07。

## 本轮变化

- 移除安全间隙设置及额外尺寸计算；使用用户填写的外包尺寸。
- 普通货物改为每排数量×纵向排数（层）与合计，推荐数字常显于占位提示；托盘和木箱仍直接输入数量。
- 先摆托盘，再建立不重叠的侧面和上方空间，逐个空间选择货物、输入排布、计算数量。
- 加入分节剖面和3D托盘透视轮廓，避免居中或靠左的底座被前方货物完全遮挡。
- 允许最多100mm长度差的上方规划，并提供关闭选项及支撑/承重提示；不把该选项视为实际装柜安全认证。
- 旧方案保留，空间变化后失效的分配明确提示重新选择。没有数据库结构迁移，也未重做其它业务模块。

## 验证

- `flutter analyze`：0 issues。
- `flutter test`：145项全部通过，日志 `artifacts/container-loading-v3-tests.log`。
- UI专项11项通过，涵盖空间选货、乘积输入、确认和保存；最终全量测试包含这些用例。
- 测试规格：两个2800×1200×1000托盘叠放，2900×160×160 PVC，2900×2200×2690分节。居中为48+28+48=124件，靠边为96+28=124件；上方确实生成28件的3D组。关闭悬出后为96件。超过100mm长度差时不强行放上方。
- 测试数据与用户真实业务数据分开；截图来自自动化内存数据库验收场景。

## 截图

- `docs/screenshots/container_loading_v3/v3_third_section_left.png`
- `docs/screenshots/container_loading_v3/v3_third_section_center.png`
- `docs/screenshots/container_loading_v3/v3_third_section_right.png`

算法、旧数据兼容和JSON版本字段详见 `docs/tools/container_loading_v3.md`。复杂多底座为保守分区，非数学最优装箱。

## 发布与启动

- Windows Release 混淆构建通过，日志 `artifacts/container-loading-v3-build.log`。
- 最终截图专项2项通过，日志 `artifacts/container-loading-v3-screenshots.log`；三种位置截图已检查。
- 安装包 `dist/Fly-Setup-1.0.0.exe`，12,122,662 bytes。
- SHA-256：`7D68299D3FA450ED3E2B3DFD6787FF9E6DF19198F6F18C20091E73CFE12D6C68`。
- 2026-09-07 09:29:43 已启动 `build/windows/x64/runner/Release/fly.exe`，PID6920，窗口标题Fly，Responding=True；保持运行供测试。
- 安装包未签名，Windows可能提示未知发布者。实际启动验证与自动化场景截图分别完成。
