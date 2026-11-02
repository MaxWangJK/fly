/// Six visible stages; legacy definitions and stored records remain recoverable.
abstract final class OrderLifecycle {
  static const pending = 'order-awaiting-deposit';
  static const stages = [
    (pending, '待付款', 'Awaiting payment', 0xFFD1904A),
    ('order-production', '生产中', 'In production', 0xFF4D6BD8),
    ('order-awaiting-shipment', '待发货', 'Awaiting shipment', 0xFF3C8D87),
    ('order-shipped', '已发货', 'Shipped', 0xFF4A889E),
    ('order-completed', '已完成', 'Completed', 0xFF5F8D78),
    ('order-cancelled', '已取消', 'Cancelled', 0xFF9A6A6A),
  ];

  static String normalize(String? id) => switch (id) {
    'order-balance-received' => 'order-awaiting-shipment',
    _ => stages.any((s) => s.$1 == id) ? id! : pending,
  };

  static String label(String? id, {required bool zh}) {
    final stage = stages.firstWhere((s) => s.$1 == normalize(id));
    return zh ? stage.$2 : stage.$3;
  }
}
