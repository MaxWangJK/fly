/// Initial defaults. Persisted definitions may be renamed, disabled or extended.
abstract final class CustomerLifecycle {
  static const stages = [
    ('customer-new', '新客户', 'New customer', 0xFF6B7A90),
    ('customer-developing', '开发中', 'Developing', 0xFF4D6BD8),
    ('customer-intent', '意向客户', 'Interested', 0xFF5F8D78),
    ('customer-won', '成交客户', 'Customer', 0xFF3D8A69),
    ('customer-repeat', '复购客户', 'Repeat customer', 0xFF397A61),
  ];
  static const legacyIds = {
    'customer-inquiry',
    'customer-followup',
    'customer-quoted',
    'customer-sample',
  };
  static String normalize(String? id) => switch (id) {
    null || '' => 'customer-new',
    'customer-inquiry' || 'customer-followup' => 'customer-developing',
    'customer-quoted' || 'customer-sample' => 'customer-intent',
    _ => id,
  };
  static String label(String? id, {required bool zh, String? customName}) {
    final stage = stages.where((s) => s.$1 == normalize(id)).firstOrNull;
    if (customName != null && (stage == null || customName != stage.$2)) {
      return customName;
    }
    return stage == null
        ? (zh ? '其他状态' : 'Other status')
        : (zh ? stage.$2 : stage.$3);
  }
}
