# Container Loading V2 信息架构

沿用 Primary Rail → Tool Sidebar → Loading Editor → 3D Scene。工具只包含装柜模拟。

Sidebar 顺序：装柜模拟、集装箱（含添加/编辑/恢复默认）、保存方案（最近修改五条，更多展开）、货物库（编辑/复制规格/软删除/拖动）。

箱型选择只在 Sidebar。Editor 顶部显示当前尺寸、载重、间隙、节数和未分配长度。每节拥有自己的数量、摆放设置及自动装柜按钮。唯一“保存方案”入口固定在 Editor 底部，不随分节列表滚走；同时显示装载数量、未保存状态和“处理未装”入口。Ctrl+S 保留。

切换箱型或方案前，有未保存修改时确认放弃。删除保存方案只软删除 Plan，不删除 Cargo 或 Container。
