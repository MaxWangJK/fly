<?php
declare(strict_types=1);

// Prices are in RMB cents. Zero means the plan is displayed but cannot be sold.
return [
    'basic' => [
        'name' => '基础版',
        'subtitle' => '让每一天的工作有序推进',
        'modules' => ['tasks', 'calendar', 'matrix'],
        'features' => ['任务清单与提醒', '日历安排', '重要紧急四象限'],
        'price_cents' => (int) (getenv('FLY_PRICE_BASIC_CENTS') ?: 0),
        'rank' => 1,
    ],
    'pro' => [
        'name' => '高级版',
        'subtitle' => '从客户跟进走到订单交付',
        'modules' => ['tasks', 'calendar', 'matrix', 'dashboard', 'crm', 'orders', 'files', 'notes', 'review', 'container'],
        'features' => ['包含基础版全部能力', '工作概览、客户与订单', '收款与预计利润', '文件、笔记与今日复盘', '3D 装柜规划'],
        'price_cents' => (int) (getenv('FLY_PRICE_PRO_CENTS') ?: 0),
        'rank' => 2,
    ],
];
