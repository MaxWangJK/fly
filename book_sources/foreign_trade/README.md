# 外贸工作手册：创作源

本目录属于作者工程，不放入 Flutter 资源或客户安装包。第一版以工程内 14 篇原创外贸资料为基础，整理为 16 章，增加导读、实践任务、工作表、原创流程图与纸纹背景。现有个人笔记只有空的关联笔记，没有另外一份完整书稿；本书没有读取客户、订单或真实联系人内容。

- `book.json`：书籍身份、版本、目录。目录只包含章节，不增加子目录。
- `chapters/*.html`：可编辑 HTML 正文片段。修改正文时保留章节 ID，阅读进度才能继续关联。
- `styles/book.css`：作者样式。允许本地配套图片，不允许脚本、远程资源或外部样式导入。
- `assets/*.png`：原创插图与背景。发布时全部进入加密包，不成为阅读器数据目录中的独立文件。

修改后增加 `book.json` 的整数 `version`，从工程根目录发布：

```sh
dart run tool/build_fly_book.dart book_sources/foreign_trade dist/Fly-Foreign-Trade-Fieldbook-v1.fly
```

发布工具使用原有 `license_tools/private/knowledge_signing.key`，不会替换签发身份。首次发布会在同一个 Git 忽略目录生成 `book_build_defines.json`，其中包含书籍内容密钥和验签公钥。两份内部文件必须安全备份；不要发给读者，不要提交 Git。新 Mac 应安全迁移原文件，不能重新生成覆盖它们。

支持本书的应用需带上 `--dart-define-from-file=license_tools/private/book_build_defines.json` 构建；这个配置只用于编译，不复制到应用安装目录。作者源 HTML/图片与密钥也不复制到客户包。

初稿生成入口 `tool/curate_trade_book.dart` 会在已有 `book.json` 时拒绝覆盖。后续写作直接编辑本目录；不要为了重新发布而重新生成书稿。

这是离线内容保护，不能保证绝对防破解。执行程序必须解密显示内容，专业逆向、内存抓取、截图或 OCR 仍可能获取内容。不要把界面的复制限制理解为不可提取。

素材文件名使用英文字母、数字、短横线或下划线；图片放在 assets/ 下，支持 PNG、JPEG、GIF、WebP。HTML 使用 UTF-8 正文片段，CSS 放在独立样式文件。
