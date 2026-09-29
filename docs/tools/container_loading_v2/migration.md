# Schema 9 → 10

新增 container_sections 与 section_cargo_entries，Cargo 增加 default_section_quantity，Group 增加 section_id/entry_id/needs_review/allow_stack。

旧方案根据箱长创建默认 2900 mm 分节；40HQ 四节并保留 300 mm，20GP 两节。旧 Group 若完整位于对应的 X 区间，关联该节；否则关联第一节并 needsReview=true。

旧位置、数量、尺寸、旋转与颜色原样保留。为每个旧组建立 Entry 及货物快照。迁移不删除旧方案，也不修改其它业务表的数据。

保存 V2 Plan 使用数据库事务同时写 Plan、Sections、Entries 和 Groups；失败回滚。删除方案为软删除，货物库和箱型独立保留。
