import 'package:flutter/material.dart';

import '../../../shared/design_system/fly_color_scheme.dart';

class KnowledgeSopNode {
  const KnowledgeSopNode(this.zh, this.en, this.categoryId, [this.articleId]);
  final String zh;
  final String en;
  final String categoryId;
  final String? articleId;
}

const knowledgeSopNodes = <KnowledgeSopNode>[
  KnowledgeSopNode('线索来源', 'Lead sources', 'lead-sources'),
  KnowledgeSopNode(
    '客户筛选',
    'Lead screening',
    'lead-screening',
    'lead-screening',
  ),
  KnowledgeSopNode(
    '客户背调',
    'Customer research',
    'lead-background',
    'customer-background',
  ),
  KnowledgeSopNode('客户分层', 'Customer tiers', 'lead-tiering'),
  KnowledgeSopNode('首次触达', 'First contact', 'comm-first', 'first-contact'),
  KnowledgeSopNode('需求确认', 'Needs discovery', 'comm-needs'),
  KnowledgeSopNode(
    '报价前沟通',
    'Before quoting',
    'comm-before-quote',
    'before-quote',
  ),
  KnowledgeSopNode('产品价值表达', 'Product value', 'comm-fabe', 'product-value'),
  KnowledgeSopNode('报价', 'Quotation', 'comm-quote', 'before-quote'),
  KnowledgeSopNode(
    '报价后跟进',
    'Quote follow-up',
    'comm-followup',
    'quote-followup',
  ),
  KnowledgeSopNode(
    '异议处理',
    'Handle objections',
    'comm-price',
    'price-objection',
  ),
  KnowledgeSopNode(
    '价格谈判',
    'Price negotiation',
    'comm-price',
    'price-objection',
  ),
  KnowledgeSopNode('样品 / 打样', 'Sampling', 'comm-sample', 'sample-progress'),
  KnowledgeSopNode(
    '推进订单',
    'Advance the order',
    'comm-nudge',
    'natural-order-nudge',
  ),
  KnowledgeSopNode('收款', 'Collect payment', 'comm-payment', 'payment-followup'),
  KnowledgeSopNode('生产 / 订单执行', 'Production / execution', 'execution'),
  KnowledgeSopNode('装柜 / 出货', 'Loading / shipment', 'exec-loading'),
  KnowledgeSopNode('售后', 'After-sales', 'exec-after-sales'),
  KnowledgeSopNode(
    '复购 / 增量',
    'Repeat / expand',
    'exec-repeat',
    'reactivate-customer',
  ),
  KnowledgeSopNode(
    '老客户唤醒',
    'Reactivate customers',
    'comm-silent',
    'reactivate-customer',
  ),
];

const knowledgeSopBranches = <KnowledgeSopNode>[
  KnowledgeSopNode('客户长期不回复', 'Long silence', 'comm-silent', 'silent-customer'),
  KnowledgeSopNode('沉默客户唤醒', 'Re-engage', 'comm-silent', 'reactivate-customer'),
  KnowledgeSopNode('输单', 'Lost deal', 'comm-lost', 'lost-deal-review'),
  KnowledgeSopNode(
    '输单复盘',
    'Lost-deal review',
    'growth-lost',
    'lost-deal-review',
  ),
];

class KnowledgeSopMap extends StatelessWidget {
  const KnowledgeSopMap({
    required this.isZh,
    required this.onSelect,
    super.key,
  });
  final bool isZh;
  final ValueChanged<KnowledgeSopNode> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.flyColors;
    Widget node(KnowledgeSopNode item, int index, {bool branch = false}) =>
        Semantics(
          button: true,
          label: isZh ? item.zh : item.en,
          child: InkWell(
            key: ValueKey('sop-${branch ? 'branch' : 'main'}-$index'),
            onTap: () => onSelect(item),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
              decoration: BoxDecoration(
                color: branch ? colors.surfaceMuted : colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.divider),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: colors.selected,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(fontSize: 12, color: colors.accent),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isZh ? item.zh : item.en,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 56),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isZh ? '外贸 SOP 地图' : 'Trade SOP map',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 9),
              Text(
                isZh ? '点击任一阶段，进入对应方法和文章。流程是导航，不会自动修改客户或订单。' : 'Select a stage to open its methods and articles. This map never changes customer or order data.',
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 28),
              for (var i = 0; i < knowledgeSopNodes.length; i++) ...[
                node(knowledgeSopNodes[i], i),
                if (i < knowledgeSopNodes.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 31),
                    child: SizedBox(
                      height: 24,
                      child: VerticalDivider(
                        color: colors.accent,
                        thickness: 1.5,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 38),
              Text(
                isZh ? '特殊分支' : 'Alternative paths',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < knowledgeSopBranches.length; i++) ...[
                node(knowledgeSopBranches[i], i, branch: true),
                if (i < knowledgeSopBranches.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 31),
                    child: SizedBox(
                      height: 20,
                      child: VerticalDivider(color: colors.divider),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
