# Windows 文件拖放评估

2026-09-08，V9 设计阶段。

现有 desktop_drop 0.8.3 用于拖入；其已安装 Dart 导出入口是 DropTarget/DropItem，不提供本任务所需的系统拖出完整能力。Flutter Draggable 只解决应用内部的 File → Folder，不等于 Windows 文件拖出。

选择：沿用 desktop_drop 接收；通过独立 Windows 平台通道实现真实文件剪贴板与 OLE 拖出，Dart 业务层仅传文件路径，不直接操作 Win32。

实现协议：已有文件使用 CF_HDROP，UTF-16 DROPFILES 与双零结尾路径列表。拖出使用 IDataObject / IDropSource / DoDragDrop，支持取消，默认 COPY，不允许外部 MOVE 删除 Fly 托管原件。Ctrl+C 发布文件载荷，另提供复制路径；内部剪切使用文件 ID，粘贴成功后才移动目录关系。

不自动发送到通讯应用；只提供由用户拖放/粘贴触发的数据。目标应用是否接受以及权限等级差异须在桌面、Explorer、通讯应用分别人工验证。开发完成前不得声称通讯应用已通过测试。

参考 Microsoft 官方协议：

- [Shell Clipboard Formats](https://learn.microsoft.com/en-us/windows/win32/shell/clipboard)
- [Shell Drag-and-Drop](https://learn.microsoft.com/en-us/windows/win32/shell/dragdrop)

验收：多文件、中文/空格文件名、取消、丢失文件、不同权限目标、粘贴、应用退出后的剪贴板寿命。文件路径必须验证为实际存在的文件；文件内容不整体装载进 Dart 内存。

实现进度：当前实现为单选文件，由 Windows Shell 的 IShellItem::BindToHandler(BHID_DataObject) 创建系统 IDataObject，而非手写 DROPFILES 内存。复制使用 OleSetClipboard + OleFlushClipboard；拖出通过独立小图标手势触发 DoDragDrop，只提供 COPY。Windows Release 编译链接已通过；多文件选择和 Explorer/通讯应用实测尚未验收。

系统对象依据：[Microsoft IShellItem::BindToHandler](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ishellitem-bindtohandler)。

2026-09-09 验证记录：增加 `tool/v9_native_smoke.dart`，使用临时目录、内存数据库和合成的中文/空格文件名，不读取正式数据。Debug 构建通过，窗口的可访问树确认显示“V9 文件传输验证（隔离数据）”及测试文件。当前桌面控制返回 `SetIsBorderRequired ... 0x80004002`，无截图时点击仍返回 `coordinate input geometry is unavailable`。因此未完成 Explorer 粘贴或跨窗口拖出，不能视为通过；未向通讯应用发送文件。
