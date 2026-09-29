# 装柜模拟 V6：过滤不可实用的小余隙

## 原因

用户截图的推荐数量正确，问题是 V5 将所有正尺寸余隙都作为继续装货的提示。

- PVC：宽 1000mm / 250mm = 4 件；高 2690mm / 100mm 向下取整为 26 层，留下高 90mm。
- WPC：宽 1200mm / 160mm 向下取整为 7 件；高 1890mm / 120mm 向下取整为 15 层，留下高 90mm、侧面宽 80mm。
- 所以推荐装载量是 104 + 105，加 1 个托盘共 210 件；不能通过增加一排或一层消除余隙而不越界。

## 修复

- 宽或高任一不足 500mm 的空闲空间不再显示装货卡片或剖面编号；恰好 500mm 保留。
- 宽、高均达到 500mm 的剩余空间继续正常显示，支持继续选货。
- 空间编号按可见顺序连续排列，列表与剖面使用同一组可见空间。
- 不改变实际包装尺寸、装载数量、碰撞检查、重量或利用率；不把小余隙伪算为已装满。
- 计算层保留精确空间和稳定标识。旧方案中已经分配货物的小空间及其父空间继续显示，但不再提供追加货物入口，避免隐藏用户已有分配。
- 无数据库升级、无数据删除，不修改任务、日历、CRM 等模块。

## 验证

- 截图场景回归：4 × 26 和 7 × 15，总计 210 件，已装 210，未装 0，仅显示 01 / 02。
- 499 / 500mm 宽高边界、旧小空间分配保留、可见编号连续性。
- 截图测试通过，图为内存测试数据生成的真实 Flutter UI：
  [推荐数量不再出现 03 / 04 / 05](../screenshots/container_loading_v6/v6_recommended_grids_no_small_spaces.png)。

- 静态检查通过：`artifacts/container-loading-v6-analyze.log`。
- 全量测试 153 项通过：`artifacts/container-loading-v6-tests.log`。
- 截图验收测试 2 项通过：`artifacts/container-loading-v6-screenshots.log`。
- Windows Release 和安装包生成通过：`artifacts/container-loading-v6-build.log`、`artifacts/container-loading-v6-installer.log`。
- 安装包：`dist/Fly-Setup-1.0.0.exe`（未签名）。SHA256：`683A82567EC166C7E7BB7EFA97D1C66C2A5FCCD2191A2EEE8F68AB4E8C810358`。
