<?php
declare(strict_types=1);

namespace FlyWeb;

function headerHtml(string $title, string $description): void
{
    echo '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">';
    echo '<meta name="description" content="' . e($description) . '"><meta name="theme-color" content="#f5f2ec">';
    echo '<title>' . e($title) . ' · Fly 外贸工作台</title><link rel="icon" type="image/svg+xml" href="/assets/favicon.svg">';
    $cssVersion = substr((string) hash_file('sha256', __DIR__ . '/../public/assets/site.css'), 0, 12);
    echo '<link rel="stylesheet" href="/assets/site.css?v=' . e($cssVersion) . '"><script src="/assets/site.js" defer></script></head><body>';
    echo '<a class="skip-link" href="#main">跳转到正文</a><header class="site-header"><div class="nav-shell">';
    echo '<a class="brand" href="/" aria-label="Fly 首页"><span class="brand-mark">✳</span><span>fly<span class="brand-dot">.</span></span></a>';
    echo '<button class="menu-toggle" type="button" aria-label="打开导航" aria-expanded="false" aria-controls="main-nav"><span></span><span></span></button>';
    echo '<nav id="main-nav" class="main-nav" aria-label="主导航"><a href="/#why">为什么选择 Fly</a><a href="/#features">功能</a><a href="/#screens">软件界面</a><a href="/download">下载 Fly</a><a href="/#pricing">购买方案</a></nav>';
    echo '<div class="nav-actions">';
    echo '<a class="nav-login" href="/account">客户中心</a><a class="nav-cta" href="/#pricing">了解方案 <span aria-hidden="true">↗</span></a></div></div></header>';
}

function footerHtml(): void
{
    echo '<footer class="site-footer"><div class="footer-top"><div><a class="brand brand-footer" href="/"><span class="brand-mark">✳</span><span>fly<span class="brand-dot">.</span></span></a><p>让外贸日常，有迹可循。</p><br><br><a class="text-color" href="https://beian.mps.gov.cn/#/query/webSearch?code=11011502040971" target="_blank" rel="noopener">京公网安备11011502040971号</a></div>';
    echo '<a class="text-color">联系电话：18368366913</a><div class="footer-links"><a href="/#features">产品功能</a><a href="/#screens">真实界面</a><a href="/download">下载 Fly</a><a href="/#pricing">购买方案</a><a href="/account">客户中心</a></div></div>';
    echo '<div class="footer-bottom"><span>© ' . date('Y') . ' Fly. 跨设备工作台。</span><span>演示截图均使用虚构业务数据。装柜结果仅供规划参考。</span></div></footer></body></html>';
}

function downloadPlatforms(): array
{
    $platforms = [
        ['name' => 'Windows 10', 'type' => '桌面安装包', 'file' => 'Fly-Windows10-x64.exe', 'icon' => '▦', 'description' => '在电脑上展开完整的 Fly 工作空间。'],
        ['name' => 'Android', 'type' => '手机安装包', 'file' => 'Fly-Android.apk', 'icon' => '◫', 'description' => '随身查看任务与业务信息。'],
        ['name' => 'macOS', 'type' => 'Mac 安装包', 'file' => 'Fly-macOS.dmg', 'icon' => '⌘', 'description' => '在 Mac 上使用 Fly 的桌面工作空间。'],
    ];
    foreach ($platforms as &$platform) {
        $path = __DIR__ . '/../public/downloads/' . $platform['file'];
        $platform['available'] = is_file($path) && is_readable($path) && filesize($path) > 0;
        $platform['size'] = $platform['available'] ? number_format((float) filesize($path) / 1048576, 1) . ' MB' : null;
        $platform['url'] = '/downloads/' . rawurlencode($platform['file']);
    }
    unset($platform);
    return $platforms;
}

function downloadCards(): void
{
    foreach (downloadPlatforms() as $platform) {
        $available = $platform['available'];
        echo '<article class="download-card"><div class="download-card-top"><span class="download-icon" aria-hidden="true">' . e($platform['icon']) . '</span><span class="download-status' . ($available ? ' is-ready' : '') . '">' . ($available ? '现已提供' : '即将开放') . '</span></div>';
        echo '<div class="download-card-body"><span class="download-type">' . e($platform['type']) . '</span><h3>' . e($platform['name']) . '</h3><p>' . e($platform['description']) . '</p></div>';
        if ($available) {
            echo '<a class="download-button" href="' . e($platform['url']) . '" download>下载 ' . e($platform['name']) . '<span aria-hidden="true">↓</span></a>';
            echo '<div class="download-file">' . e($platform['file']) . ' · ' . e($platform['size']) . '</div>';
        } else {
            echo '<span class="download-button is-disabled" aria-disabled="true">安装包准备中<span aria-hidden="true">↗</span></span>';
            echo '<div class="download-file">安装包上传后自动开放</div>';
        }
        echo '</article>';
    }
}

function downloadPage(): void
{
    headerHtml('下载 Fly', '选择适合你的 Fly 安装包：Windows 10、Android 或 macOS。');
    ?>
    <main id="main" class="download-page">
      <section class="download-page-hero"><div class="download-page-hero-inner"><div class="eyebrow light"><span class="eyebrow-line"></span> DOWNLOAD FLY</div><h1>选择你的设备，<br><em>开始使用 Fly。</em></h1><p>在电脑与手机之间，找到适合你的 Fly。选择平台，下载对应安装包。</p></div></section>
      <section class="section downloads-section download-page-list" id="downloads"><div class="download-grid"><?php downloadCards(); ?></div><p class="download-note">请根据设备系统选择安装包。Android 安装 APK 时可能需要在系统设置中允许从浏览器安装应用；安装前请确认文件来源为 Fly 官网。</p></section>
    </main>
    <?php
    footerHtml();
}

function homePage(): void
{
    $catalog = Config::catalog();
    headerHtml('把外贸日常，放进一个工作台', 'Fly 是面向个人外贸业务的工作台，集中管理客户、订单、任务日历、文件笔记与 3D 装柜规划。');
    ?>
    <main id="main">
      <section class="hero">
        <div class="hero-glow"></div>
        <div class="hero-inner">
          <div class="hero-copy">
            <div class="eyebrow light"><span class="eyebrow-line"></span> FOR THE WAY YOU WORK</div>
            <h1>让每一条线索，<br><em>都有清晰的下一步。</em></h1>
            <p>客户跟进、订单执行、收款费用与每日安排，不再散落在不同角落。Fly 把外贸人的日常，收拢成一个从容的工作台。</p>
            <div class="hero-actions"><a class="button button-light" href="#features">探索 Fly <span>↗</span></a><a class="button button-ghost" href="#screens">看看真实界面 <span>→</span></a></div>
            <div class="hero-proof"><span class="proof-icon">✦</span><span>为个人外贸业务员与 SOHO 而设计</span></div>
          </div>
          <div class="hero-visual"><div class="visual-orbit orbit-one"></div><div class="visual-orbit orbit-two"></div><div class="app-frame"><div class="frame-bar"><div class="frame-dots"><i></i><i></i><i></i></div><span>Fly · 客户工作区</span><span>↗</span></div><img src="/assets/screens/customer.png" alt="Fly 客户跟进真实界面，含客户列表、下次行动与关联订单" width="1400" height="820"></div><div class="float-card float-card-top"><span class="float-symbol">↗</span><span>客户进展<br><strong>一眼清晰</strong></span></div><div class="float-card float-card-bottom"><span class="float-symbol">✓</span><span>下一步<br><strong>始终明确</strong></span></div></div>
        </div>
        <div class="hero-bottom"><span>01 / 一个工作台，串起整个外贸流程</span><a href="#why" aria-label="继续向下浏览">SCROLL TO EXPLORE <span>↓</span></a></div>
      </section>

      <div class="fact-strip"><div><span class="fact-number">01</span><span>Windows · Android · macOS</span></div><div><span class="fact-number">02</span><span>业务资料本地保存</span></div><div><span class="fact-number">03</span><span>每份授权最多 3 台设备</span></div><div><span class="fact-number">04</span><span>计划提供永久买断</span></div></div>

      <section class="section intro" id="why"><div class="section-label"><span>01 / WHY FLY</span><span class="line"></span></div><div class="intro-grid"><div><h2>一个人的外贸，<br><em>也值得专业系统。</em></h2></div><div class="intro-right"><p class="large-copy">业务越忙，信息越容易分散。真正顺手的工具，应该让你随时知道：现在要联系谁，订单走到哪一步，接下来做什么。</p><p>Fly 从个人工作场景出发，把客户、订单与计划放在同一个上下文里。打开工作台，重要的事自然浮现。</p></div></div><div class="principles"><article><span class="principle-index">01</span><div class="principle-icon">◎</div><h3>关系有脉络</h3><p>跟进记录、下一步安排和关联订单，围绕客户持续沉淀。</p></article><article><span class="principle-index">02</span><div class="principle-icon">▣</div><h3>进度看得见</h3><p>从工厂、产品到收款费用，订单执行状态清楚可查。</p></article><article><span class="principle-index">03</span><div class="principle-icon">✳</div><h3>工作有节奏</h3><p>用任务、日历与四象限，把今天和下一步安排妥当。</p></article></div></section>

      <section class="feature-section" id="features"><div class="section feature-heading"><div class="section-label"><span>02 / THE WORKSPACE</span><span class="line"></span></div><div class="feature-title-row"><h2>从客户初识，<br>到每一次交付。</h2><p>日常业务的关键步骤，在 Fly 里自然衔接。</p></div></div>
        <div class="feature-story"><div class="story-copy"><span class="story-kicker">01 / 客户跟进</span><h3>重要的客户，<br><em>记住每一次联系。</em></h3><p>把联系人、客户分级、沟通记录与下一步动作放在一起。按今天、未来 7 天和客户级别整理待跟进事项。</p><ul><li>清楚查看下一次联系时间</li><li>保留历史跟进与关联订单</li><li>用标签与搜索快速定位</li></ul></div><div class="story-image"><img src="/assets/screens/customer.png" alt="Fly 客户管理真实截图" loading="lazy" width="1400" height="820"><span class="image-caption">FLY / CUSTOMER WORKSPACE</span></div></div>
        <div class="feature-story reverse"><div class="story-copy"><span class="story-kicker">02 / 订单执行</span><h3>每笔订单，<br><em>都有完整来路。</em></h3><p>客户、工厂、产品和订单状态集中查看，收款与费用逐笔记录。需要核对进度时，不再靠记忆拼凑。</p><ul><li>订单与客户双向关联</li><li>记录定金、尾款和成本费用</li><li>归档 PI、CI、PL 等业务文件</li></ul></div><div class="story-image"><img src="/assets/screens/orders.png" alt="Fly 订单执行真实截图" loading="lazy" width="1400" height="820"><span class="image-caption">FLY / ORDER FLOW</span></div></div>
        <div class="feature-story"><div class="story-copy"><span class="story-kicker">03 / 任务管理</span><h3>每一件待办，<br><em>都有明确进度。</em></h3><p>把报价更新、样品确认、出货资料等工作放进任务清单。用日期、提醒和优先级安排节奏，重复事项也能持续跟进。</p><ul><li>按清单和标签整理待办</li><li>设置日期、提醒与重复规则</li><li>完成任务后保留清楚的状态</li></ul></div><div class="story-image"><img src="/assets/screens/tasks.png" alt="Fly 任务清单真实截图" loading="lazy" width="1400" height="820"><span class="image-caption">FLY / TASKS</span></div></div>
        <div class="feature-story reverse"><div class="story-copy"><span class="story-kicker">04 / 日历视图</span><h3>每天的安排，<br><em>看得见，也调得动。</em></h3><p>用月历查看任务落在哪一天，提前发现忙碌和空档。选定日期就能快速添加任务，也可以调整已有任务的日期。</p><ul><li>月视图查看工作分布</li><li>按日期快速新建任务</li><li>调整任务日期，安排下一步</li></ul></div><div class="story-image"><img src="/assets/screens/calendar.png" alt="Fly 月历任务视图真实截图" loading="lazy" width="1400" height="820"><span class="image-caption">FLY / CALENDAR</span></div></div>
        <div class="feature-story"><div class="story-copy"><span class="story-kicker">05 / 四象限</span><h3>分清轻重缓急，<br><em>先做重要的事。</em></h3><p>用重要与紧急两个维度整理任务，让关键事项先进入视线。任务可在象限中直接处理，也能拖动调整重要与紧急状态。</p><ul><li>四类事项分区呈现</li><li>拖动任务调整所在象限</li><li>在象限中直接处理待办</li></ul></div><div class="story-image"><img src="/assets/screens/matrix.png" alt="Fly 重要紧急四象限真实截图" loading="lazy" width="1400" height="820"><span class="image-caption">FLY / PRIORITY MATRIX</span></div></div>
      </section>

      <section class="tool-highlight"><div class="tool-inner"><div class="tool-copy"><span class="story-kicker">06 / 装柜规划</span><h2>把装柜方案，<br><em>提前看清。</em></h2><p>按货物、托盘与分节规划装载，在 3D 空间里观察摆放和剩余空间。方案可保存，也能继续调整。</p><a class="text-link" href="#screens">查看更多软件界面 <span>↗</span></a></div><div class="tool-image"><img src="/assets/screens/container.png" alt="Fly 3D 装柜规划真实截图" loading="lazy" width="1400" height="820"></div></div><div class="tool-note">装柜模拟仅供规划参考，实际装载需核验尺寸、支撑与承重。</div></section>

      <section class="section gallery" id="screens"><div class="section-label"><span>03 / INSIDE FLY</span><span class="line"></span></div><div class="gallery-heading"><div><h2>真实界面，<br><em>真实工作感。</em></h2><p>以下截图来自 Fly 桌面应用，内容使用演示数据。</p></div><span class="gallery-count">01 — 07</span></div><div class="gallery-tabs" role="tablist" aria-label="软件截图"><button type="button" class="active" role="tab" aria-selected="true" data-screen="customer">客户跟进</button><button type="button" role="tab" aria-selected="false" data-screen="orders">订单执行</button><button type="button" role="tab" aria-selected="false" data-screen="finance">收款利润</button><button type="button" role="tab" aria-selected="false" data-screen="tasks">任务清单</button><button type="button" role="tab" aria-selected="false" data-screen="calendar">日历视图</button><button type="button" role="tab" aria-selected="false" data-screen="matrix">四象限</button><button type="button" role="tab" aria-selected="false" data-screen="container">装柜规划</button></div><div class="gallery-display"><div class="gallery-window"><div class="frame-bar"><div class="frame-dots"><i></i><i></i><i></i></div><span id="gallery-window-title">Fly · 客户跟进</span><span>↗</span></div><a id="gallery-link" href="/assets/screens/customer.png" target="_blank" rel="noopener"><img id="gallery-image" src="/assets/screens/customer.png" alt="Fly 客户跟进真实界面" width="1400" height="820" loading="lazy"></a></div><div class="gallery-description"><span id="gallery-index">01 / 07</span><div><h3 id="gallery-title">客户跟进，清楚下一步</h3><p id="gallery-copy">在同一个视图里查看待联系客户、记录与下一次行动。</p></div><a id="gallery-open" href="/assets/screens/customer.png" target="_blank" rel="noopener">查看大图 ↗</a></div></div></section>

      <section class="quiet-band"><div><span class="quiet-star">✳</span><h2>信息留在手边，<br>节奏握在自己手里。</h2></div><p>Fly 以本地数据为基础。桌面端的业务资料与文件保存在你选择的 FlyData 目录，并提供备份和恢复入口。</p></section>

      <section class="section downloads-section" id="downloads"><div class="section-label"><span>DOWNLOAD / GET FLY</span><span class="line"></span></div><div class="downloads-heading"><div><h2>选择你的设备，<br><em>开始使用 Fly。</em></h2><p>电脑与手机，找到适合你的安装包。文件就绪后，这里会直接提供下载。</p></div><span class="downloads-mark" aria-hidden="true">↓</span></div><div class="download-grid"><?php downloadCards(); ?></div><p class="download-note">请根据设备系统选择安装包。Android 安装 APK 时可能需要在系统设置中允许从浏览器安装应用；安装前请确认文件来源为 Fly 官网。</p></section>

      <section class="section pricing" id="pricing"><div class="section-label"><span>04 / PLANS</span><span class="line"></span></div><div class="pricing-heading"><div><h2>选择适合你的<br><em>工作方式。</em></h2><p>永久买断方案规划中。每个账户最多绑定 3 台设备，具体价格将在上线前公布。</p></div><div class="pricing-stamp">ONE TIME<br>YOUR WAY ↗</div></div><div class="price-grid">
      <?php foreach ($catalog as $sku => $plan): ?>
        <article class="price-card <?= $sku === 'pro' ? 'featured' : '' ?>"><div class="price-card-top"><span><?= $sku === 'pro' ? '完整业务工作台' : '从日常计划开始' ?></span><span><?= $sku === 'pro' ? '✳' : '↗' ?></span></div><h3><?= e($plan['name']) ?></h3><p class="price-subtitle"><?= e($plan['subtitle']) ?></p><div class="price-value"><?= $plan['price_cents'] > 0 ? '<small>¥</small>' . e(number_format($plan['price_cents'] / 100, 2)) : '<span>价格待公布</span>' ?></div><div class="price-meta">一次购买 · 最多 3 台设备</div><a class="price-action" href="/account">购买入口筹备中 <span>↗</span></a><div class="price-divider"></div><div class="price-list-title">包含功能</div><ul><?php foreach ($plan['features'] as $feature): ?><li><span>✓</span><?= e($feature) ?></li><?php endforeach; ?></ul></article>
      <?php endforeach; ?>
      </div><p class="pricing-footnote">方案与模块划分仍在规划。正式销售前将公布最终价格、交付内容、升级与换机规则；桌面端模块授权校验也会同步完成。</p></section>

      <section class="purchase-flow"><div class="section purchase-inner"><div class="section-label"><span>05 / HOW IT WORKS</span><span class="line"></span></div><div class="flow-heading"><h2>从选择方案，<br>到开始使用。</h2><p>账户登录与付款接入仍在规划。账号入口开放后，购买和设备授权会在客户中心完成。</p></div><div class="flow-grid"><article><span>01</span><h3>登录并选择方案</h3><p>登录经过验证的客户账户，选择适合的功能方案。</p></article><article><span>02</span><h3>确认付款</h3><p>付款确认后，授权会关联到你的客户账户。</p></article><article><span>03</span><h3>输入设备码取密钥</h3><p>在客户中心提交 Fly 显示的设备码，获取对应授权密钥。</p></article></div></div></section>

      <section class="section faq"><div class="section-label"><span>06 / GOOD TO KNOW</span><span class="line"></span></div><div class="faq-grid"><div><h2>常见问题</h2><p>关于使用边界与购买流程，你可能关心这些。</p></div><div class="faq-list"><details><summary>Fly 支持哪些设备？<span>＋</span></summary><p>Windows 10、Android 和 macOS 的安装包状态以下载区为准；具体系统版本与功能范围请查看对应安装包说明。每个购买账户计划最多绑定 3 台设备，正式授权的平台范围待公布。</p></details><details><summary>数据会自动同步到云端吗？<span>＋</span></summary><p>Fly 以本地数据为基础，可主动开启云同步或电脑手机直连。云同步只传业务记录和文件信息，不上传图片或文件内容；实体文件使用同一局域网内的电脑手机直连。同步不能替代定期备份。</p></details><details><summary>基础版和高级版如何区别？<span>＋</span></summary><p>基础版规划包含任务、日历与四象限；高级版规划扩展客户、订单、工作概览、文件、笔记、今日复盘和 3D 装柜等模块。最终模块与价格以正式发布页面为准。</p></details><details><summary>付款后如何拿到授权？<span>＋</span></summary><p>账户与付款服务接入完成后，可在客户中心购买、查看订单，并输入软件内显示的设备码领取密钥。目前官网尚未开放实际付款。</p></details></div></div></section>

      <section class="closing"><div class="closing-orbit"></div><span>WORK WITH CLARITY</span><h2>把重要的工作，<br><em>放在看得见的地方。</em></h2><a class="button button-light" href="/account">走进 Fly 客户中心 <span>↗</span></a></section>
    </main>
    <?php
    footerHtml();
}

function accountPage(?string $userId, ?array $activation = null, ?string $error = null): void
{
    headerHtml('客户中心', 'Fly 客户中心：查看购买方案、设备授权和密钥领取状态。');
    echo '<main id="main" class="account-page"><div class="account-shell"><div class="section-label"><span>MY FLY / ACCOUNT</span><span class="line"></span></div><h1>你的 Fly，<br><em>由你掌握。</em></h1>';
    if ($userId === null) {
        echo '<div class="account-notice"><div class="notice-icon">✳</div><div><h2>客户中心即将开放</h2><p>账户登录接口尚未接入，因此目前无法创建订单、付款或领取密钥。接入完成后，购买与设备管理会在这里进行。</p><a class="text-link" href="/#pricing">查看购买方案 ↗</a></div></div>';
    } else {
        $db = Database::connect();
        $plan = Orders::paidPlan($db, $userId);
        echo '<div class="account-notice"><div class="notice-icon">✓</div><div><h2>' . ($plan ? '授权账户已开通' : '欢迎来到 Fly') . '</h2><p>' . ($plan ? '已购买 ' . e(Config::catalog()[$plan['sku']]['name']) . '。可为最多 3 台设备领取密钥。' : '购买后可在这里管理设备授权。') . '</p></div></div>';
        if ($error !== null) {
            echo '<p class="form-error" role="alert">' . e($error) . '</p>';
        }
        if ($activation !== null) {
            echo '<div class="token-panel"><h2>设备密钥</h2><p>复制以下完整密钥，粘贴到 Fly 的授权输入框。</p><textarea readonly rows="6" aria-label="设备密钥">' . e($activation['token']) . '</textarea><button type="button" class="copy-token">复制密钥</button></div>';
        }
        if ($plan) {
            echo '<form class="activation-form" method="post" action="/api/activate"><h2>领取设备密钥</h2><label for="machine-code">设备码</label><input id="machine-code" name="machine_code" maxlength="64" pattern="[A-Fa-f0-9]{64}" required placeholder="输入软件内显示的 64 位设备码"><input type="hidden" name="csrf" value="' . e((string) $_SESSION['csrf']) . '"><button type="submit">生成 / 查看密钥 ↗</button><p>同一台设备可重新查看密钥；新设备最多绑定 3 台。</p></form>';
            $stmt = $db->prepare('SELECT machine_code,sku,created_at FROM activations WHERE user_id = ? ORDER BY created_at');
            $stmt->execute([$userId]);
            echo '<div class="device-list"><h2>已绑定设备</h2>';
            foreach ($stmt as $device) {
                echo '<div><span>' . e(substr($device['machine_code'], 0, 12)) . '…' . e(substr($device['machine_code'], -8)) . '</span><span>' . e(Config::catalog()[$device['sku']]['name']) . '</span></div>';
            }
            echo '</div>';
        }
        if (!$plan && Config::paymentReady() && Config::value('FLY_SALES_ENABLED') === '1') {
            echo '<div class="buy-plans"><h2>选择购买方案</h2>';
            foreach (Config::catalog() as $sku => $offer) {
                if ($offer['price_cents'] < 1) {
                    continue;
                }
                echo '<form method="post" action="/api/checkout"><div><strong>' . e($offer['name']) . '</strong><span>¥' . e(number_format($offer['price_cents'] / 100, 2)) . '</span></div><input type="hidden" name="sku" value="' . e($sku) . '"><input type="hidden" name="csrf" value="' . e((string) $_SESSION['csrf']) . '"><button type="submit">购买服务筹备中 ↗</button></form>';
            }
            echo '</div>';
        }
        $stmt = $db->prepare('SELECT id,sku,amount_cents,status,created_at FROM orders WHERE user_id = ? ORDER BY created_at DESC LIMIT 20');
        $stmt->execute([$userId]);
        echo '<div class="order-list"><h2>购买记录</h2>';
        foreach ($stmt as $order) {
            echo '<div><span>' . e(Config::catalog()[$order['sku']]['name'] ?? $order['sku']) . '<small>' . e($order['id']) . '</small></span><span>¥' . e(number_format($order['amount_cents'] / 100, 2)) . ' · ' . ($order['status'] === 'paid' ? '已支付' : '待支付') . '</span></div>';
        }
        echo '</div>';
    }
    echo '<div class="account-steps"><article><span>01</span><h3>选择方案</h3><p>按工作需要选择模块。</p></article><article><span>02</span><h3>确认付款</h3><p>订单确认后开通授权。</p></article><article><span>03</span><h3>绑定设备</h3><p>输入设备码，领取专属密钥。</p></article></div><a class="back-home" href="/">← 返回官网</a></div></main>';
    footerHtml();
}
