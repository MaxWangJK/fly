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

## 双复盘与邮箱注册（2026-11-01，已纳入 build43）

双复盘：[手机选择](review-program-choice-phone.png)、[电脑选择](review-program-choice-desktop.png)、[只读浏览](review-program-preview-phone.png)、[深色窄屏卡片](review-program-card-dark-narrow.png)。

邮箱账号：[电脑登录](cloud-email-login-desktop.png)、[手机图形验证](cloud-email-captcha-phone.png)、[深色窄屏设置密码](cloud-email-password-dark-narrow.png)。使用隔离账号和测试验证码，未发送真实邮件。以上均为 Flutter 渲染，不能代替真机、真实 SMTP 或服务器部署验收。本阶段累计 37 张 PNG。

## 账号生命周期源码续补（2026-11-01，未重新打包）

[手机找回密码](cloud-account-reset-phone.png)、[电脑注销说明](cloud-account-delete-desktop.png)、[深色窄屏注销说明](cloud-account-delete-dark-narrow.png)。均为真实 Flutter 渲染、隔离账号，无实际邮件或云账号删除；手机/电脑及 1.3 倍文字已目视检查。对应源码测试还走通横屏、验证码和密码错误后重试、取消及注销勾选确认。本目录累计 40 张 PNG。


## build44 当前界面（2026-11-01）

[手机新客户](customer-create-build44-phone.png)、[桌面新客户](customer-create-build44-desktop.png)、[深色窄屏我的](my-build44-dark-narrow.png)、[简化云同步页](sync-build44-phone.png)、[桌面平面文件夹](files-flat-build44-desktop.png)、[保留基础复盘](review-basic-build44-desktop.png)、[手机客户单表头](customer-rows-build44-phone.png)。均使用隔离数据、真实 Flutter 渲染并已目视核对；深色窄屏为360×780、1.3倍文字。账号生命周期截图随本版一起交付，原生系统选图、扫码和分享仍待真机验收。


## build45（2026-11-02）

[PI新建订单](order-create-build45-desktop.png)、[深色大字订单弹框](order-create-build45-dark-large.png)、[小图标文件夹](files-folders-build45-desktop.png)。真实Flutter渲染并目视检查，1200×850浅色和840×850深色/1.3倍文字，文件夹1400×900，均为隔离业务数据。


## build46（2026-11-02）

[桌面头像与扫码图解](sync-guide-build46-desktop.png)、[手机头像与扫码图解](sync-guide-build46-phone.png)、[窄屏深色大字](sync-guide-build46-dark-large.png)。真实Flutter渲染并目视检查，1100×900、390×844、320×850/1.3倍文字。隔离数据库及合成头像，不含真实用户资料；摄像头扫码仍需真机。


## 2026-11-06 装柜实际剩余空间

真实Flutter渲染、内存测试数据、1200×1000。浅色1倍与深色1.3倍文字：
[80件上方空间](container-spaces-20261106-80-overhead-light.png)、[80件深色](container-spaces-20261106-80-overhead-dark.png)、[60件上方和侧方](container-spaces-20261106-60-two-spaces-light.png)、[60件深色](container-spaces-20261106-60-two-spaces-dark.png)。宽200mm仅余隙说明，宽700mm是装货空间；未使用真实用户方案。


## build48（2026-11-06）数量清空与移除

真实Flutter渲染，1200×1000，浅色1倍和深色1.3倍文字，均使用内存数据：
[清空第二组](cargo-input-build48-cleared-light.png)、[深色清空](cargo-input-build48-cleared-dark.png)、[移除后](cargo-input-build48-removed-light.png)、[深色移除](cargo-input-build48-removed-dark.png)。第一组80件保持，清空组为0且不占用，移除后该输入组消失，移除按钮在每组下方。


## build49（2026-11-06）区域追加及剖面右键

真实Flutter渲染，1200×1000，浅色1倍、深色1.3倍文字，内存数据：
[A/B区](cargo-area-build49-areas-light.png)、[深色A/B区](cargo-area-build49-areas-dark.png)、
[PVC160+WPC60](cargo-area-build49-loaded-light.png)、[深色装载](cargo-area-build49-loaded-dark.png)、
[右键](cargo-area-build49-menu-light.png)、[深色右键](cargo-area-build49-menu-dark.png)。
区域卡与剖面同名，空闲区域选择/拖放添加，WPC从上方加入并在3D可见，菜单提供XYZ旋转和移除。


## build51（2026-11-07）手动12×20单组与越界

真实Flutter组件、1200×1000：[浅色](manual-grid-build51-light.png)、[深色1.3倍文字](manual-grid-build51-dark.png)。
合成PVC为2900×250×100mm、20kg，柜宽2200mm。输入12×20后剖面仅标记一组PVC×240，3D同组，保留超宽800mm并标红；理论208仅供参考。


## build52（2026-11-07）紧凑文件图标

真实Flutter界面、合成图片及内存数据库、1264×800：[浅色](file-grid-build52-light.png)、[深色1.3倍文字](file-grid-build52-dark.png)。展示紧凑的层叠文件夹、完整竖图/横图、大文件类型封面和缺失图片回退；PDF封面不是正文缩略图。
