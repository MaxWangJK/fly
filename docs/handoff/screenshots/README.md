# 当前手机交互截图

2026-10-14 的实际 Flutter 组件渲染，使用隔离 SQLite 测试数据、真实图片缩略图与字体，覆盖 390×844 竖屏和 844×390 横屏。供新机/新对话理解界面，不是 Android/iOS 真机系统功能验收，也不是 macOS 截图。

| 页面 | 文件 |
| --- | --- |
| 相册 | [竖屏](files-gallery-portrait.png) |
| 多选与数量 | [横屏](files-multi-select-landscape.png) |
| 长按菜单 | [竖屏](files-actions-portrait.png) |
| 周日历与紧凑全天区 | [横屏](calendar-week-landscape.png) |
| 月日历 | [竖屏](calendar-month-portrait.png) |
| 月视图拖动后提示与撤销 | [竖屏](calendar-month-rescheduled-portrait.png) |
| 全天展开 | [竖屏](calendar-all-day-expanded-portrait.png) |
| 同步详情 | [竖屏](sync-details-portrait.png) |
| 任务入口 | [竖屏](tasks-portrait.png) |
| 客户列表 | [竖屏](customers-portrait.png) |
| 订单底部详情 | [横屏](orders-details-landscape.png) |
| 我的 | [竖屏](my-portrait.png) |

系统分享目标由已安装程序提供，本组图不会展示真实通讯应用/WhatsApp联系人；二维码、相机、原生分享、通知和外部查看器仍需真机验证。

## build 39 补充

[桌面书架](book-shelf-desktop.png)、[窄窗口书架](book-shelf-narrow.png)、[座右铭在人生主线上方](motto-focus.png)。均为实际 Flutter 渲染、隔离数据；书籍 HTML 已另在浏览器检查，并不代表系统真机全部验收。

## build 40 补充

[任务清单与右下角操作（竖屏）](tasks-inline-portrait.png)、[任务清单与右下角操作（横屏）](tasks-inline-landscape.png)、[客户新增与搜索（竖屏）](customers-actions-portrait.png)。实际 Flutter 手机布局渲染，使用隔离模拟数据；新任务在当前子清单创建，搜索输入按需展开。

## build 41 补充（2026-10-17）

[文件夹首页竖屏](files-folders-build41-portrait.png)、[文件夹首页横屏](files-folders-build41-landscape.png)、[窄屏大字清单](tasks-lists-build41-narrow.png)、[文件夹内页](files-inside-build41-portrait.png)、[扫码同步设置](sync-settings-build41-portrait.png)。使用真实 Flutter 组件及隔离数据，模拟顶部切口、横屏侧边安全区和底部手势区；窄屏为 360×780、文字缩放 1.3。目录通过真实同步记录应用后展示，不依赖内置同名占位数据。本目录共 23 张 PNG；原生切口、相机、扫码、分享和外部打开仍须 Android 真机验收。

## build 42 补充（2026-10-17）

[review-card-build42-phone.png](review-card-build42-phone.png)、[review-card-build42-desktop.png](review-card-build42-desktop.png)、[review-card-build42-dark-narrow.png](review-card-build42-dark-narrow.png)、[review-edit-build42-phone.png](review-edit-build42-phone.png)、[files-folders-build42-phone.png](files-folders-build42-phone.png)、[files-customer-add-build42-phone.png](files-customer-add-build42-phone.png)、[my-build42-phone.png](my-build42-phone.png)。均为隔离数据的 Flutter 渲染，目录三列、客户新增按钮和复盘卡片已检查，含窄屏 1.3 倍文字深色模式。共 30 张 PNG；不代替系统真机验收。
