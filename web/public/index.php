<?php
declare(strict_types=1);

use FlyWeb\Auth;
use FlyWeb\Config;
use FlyWeb\Database;
use FlyWeb\Licenses;

require_once __DIR__ . '/../src/Core.php';
require_once __DIR__ . '/../src/site.php';

header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: strict-origin-when-cross-origin');
header("Content-Security-Policy: default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; form-action 'self'; base-uri 'self'; frame-ancestors 'none'");

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

// No payment adapter is configured; callbacks cannot change orders or issue licenses.
if ($path === '/payment/notify') {
    http_response_code(410);
    header('Content-Type: text/plain; charset=utf-8');
    exit('Payment integration is not available');
}

session_name('FLYSESSID');
session_set_cookie_params([
    'httponly' => true,
    'secure' => str_starts_with(Config::baseUrl(), 'https://'),
    'samesite' => 'Lax',
    'path' => '/',
]);
session_start();
$_SESSION['csrf'] ??= bin2hex(random_bytes(32));

if ($method === 'GET' && $path === '/') {
    FlyWeb\homePage();
    exit;
}
if ($method === 'GET' && $path === '/account') {
    header('Cache-Control: no-store');
    FlyWeb\accountPage(Auth::userId());
    exit;
}
if ($method === 'GET' && $path === '/payment/return') {
    header('Cache-Control: no-store');
    FlyWeb\headerHtml('支付结果', '返回 Fly 查看购买服务状态。');
    echo '<main id="main" class="account-page"><div class="account-shell"><div class="section-label"><span>PAYMENT / STATUS</span><span class="line"></span></div><h1>已返回 Fly。</h1><div class="account-notice"><div class="notice-icon">↗</div><div><h2>请在客户中心查看订单</h2><p>页面跳转本身不代表付款成功。当前付款服务未开放；返回本页不会确认付款或发放授权。</p><a class="text-link" href="/account">前往客户中心 ↗</a></div></div></div></main>';
    FlyWeb\footerHtml();
    exit;
}
if ($method === 'GET' && $path === '/download') {
    FlyWeb\downloadPage();
    exit;
}

if (in_array($path, ['/api/checkout', '/api/activate'], true) && $method === 'POST') {
    header('Cache-Control: no-store');
    $userId = Auth::userId();
    if ($userId === null) {
        http_response_code(401);
        FlyWeb\accountPage(null);
        exit;
    }
    if (!hash_equals((string) $_SESSION['csrf'], (string) ($_POST['csrf'] ?? ''))) {
        http_response_code(403);
        exit('请求已过期，请刷新页面后重试');
    }
    try {
        if ($path === '/api/checkout') {
            http_response_code(503);
            FlyWeb\accountPage($userId, null, '购买服务尚未开放');
            exit;
        }
        $activation = Licenses::activate(Database::connect(), $userId, (string) ($_POST['machine_code'] ?? ''));
        FlyWeb\accountPage($userId, $activation);
    } catch (Throwable $e) {
        error_log('Fly account action failed: ' . $e->getMessage());
        http_response_code(400);
        FlyWeb\accountPage($userId, null, $e->getMessage());
    }
    exit;
}

http_response_code(404);
FlyWeb\headerHtml('页面未找到', '未找到该页面。');
echo '<main id="main" class="account-page"><div class="account-shell"><h1>页面走丢了。</h1><a class="text-link" href="/">返回官网 ↗</a></div></main>';
FlyWeb\footerHtml();
