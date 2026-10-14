<?php
declare(strict_types=1);

use FlyWeb\Auth;
use FlyWeb\Config;
use FlyWeb\Database;
use FlyWeb\Licenses;
use FlyWeb\Orders;

require __DIR__ . '/../src/Core.php';
require __DIR__ . '/../src/site.php';

function check(bool $condition, string $message): void
{
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

$tmp = sys_get_temp_dir() . '/fly-web-test-' . bin2hex(random_bytes(5));
mkdir($tmp, 0700);
putenv('FLY_DB_PATH=:memory:');
putenv('FLY_PRICE_BASIC_CENTS=29900');
putenv('FLY_PRICE_PRO_CENTS=59900');
putenv('FLY_BASE_URL=https://fly.example');
putenv('FLY_SALES_ENABLED=1');

$seed = random_bytes(32);
$keyPair = sodium_crypto_sign_seed_keypair($seed);
$der = hex2bin('302e020100300506032b657004220420') . $seed;
file_put_contents($tmp . '/issuer.pem', "-----BEGIN PRIVATE KEY-----\n" . chunk_split(base64_encode($der), 64, "\n") . "-----END PRIVATE KEY-----\n");
file_put_contents($tmp . '/issuer-public.txt', rtrim(strtr(base64_encode(sodium_crypto_sign_publickey($keyPair)), '+/', '-_'), '=') . "\n");
putenv('FLY_ISSUER_PRIVATE_KEY_FILE=' . $tmp . '/issuer.pem');
putenv('FLY_ISSUER_PUBLIC_KEY_FILE=' . $tmp . '/issuer-public.txt');

try {
    $db = Database::connect();
    check(!Config::paymentReady(), 'Sales flag enabled an unimplemented checkout');
    $_SESSION = [];
    check(Auth::userId() === null, 'Anonymous visitor authenticated');
    $_SESSION['fly_verified_user_id'] = '<invalid>';
    check(Auth::userId() === null, 'Invalid identity authenticated');
    $user = 'fixture_user_1234';
    $_SESSION['fly_verified_user_id'] = $user;
    $_SESSION['csrf'] = 'fixture-csrf';
    check(Auth::userId() === $user, 'Verified session was not read');
    ob_start();
    FlyWeb\homePage();
    $html = ob_get_clean();
    check(str_contains($html, '购买入口筹备中'), 'Preview checkout state is missing');
    check(!str_contains($html, 'action="/api/checkout"'), 'Homepage exposes checkout');
    $order = Orders::create($db, $user, 'basic');
    check($order['amount_cents'] === 29900, 'The configured price was not used');
    $unpaidRejected = false;
    try {
        Licenses::activate($db, $user, strtoupper(hash('sha256', 'unpaid-machine')));
    } catch (RuntimeException $e) {
        $unpaidRejected = str_contains($e->getMessage(), '先购买');
    }
    check($unpaidRejected, 'Unpaid account received a license');
    // Test fixture only. The website has no payment-confirmation endpoint.
    $stmt = $db->prepare('UPDATE orders SET status = ?, payment_reference = ?, paid_at = ? WHERE id = ?');
    $stmt->execute(['paid', 'fixture-payment-1', gmdate('c'), $order['id']]);
    $repeatPurchaseRejected = false;
    try {
        Orders::create($db, $user, 'basic');
    } catch (RuntimeException $e) {
        $repeatPurchaseRejected = str_contains($e->getMessage(), '已有永久授权');
    }
    check($repeatPurchaseRejected, 'Repeat purchase was accepted');
    for ($i = 0; $i < 3; $i++) {
        $machine = strtoupper(hash('sha256', 'test-machine-' . $i));
        $license = Licenses::activate($db, $user, $machine);
        [$body, $signatureB64] = explode('.', $license['token']);
        $payload = base64_decode(strtr($body, '-_', '+/'));
        $signature = base64_decode(strtr($signatureB64, '-_', '+/'));
        check(sodium_crypto_sign_verify_detached($signature, $payload, sodium_crypto_sign_publickey($keyPair)), 'License signature invalid');
        $decoded = json_decode($payload, true);
        check($decoded['machineCode'] === $machine && $decoded['sku'] === 'basic', 'License payload invalid');
        check(Licenses::activate($db, $user, $machine)['token'] === $license['token'], 'Repeated activation changed the token');
    }
    $fourthRejected = false;
    try {
        Licenses::activate($db, $user, strtoupper(hash('sha256', 'fourth-machine')));
    } catch (RuntimeException $e) {
        $fourthRejected = str_contains($e->getMessage(), '3 台');
    }
    check($fourthRejected, 'Fourth device was accepted');
    echo "Fly web smoke tests passed\n";
    $db = null;
} finally {
    foreach (glob($tmp . '/*') as $file) {
        unlink($file);
    }
    rmdir($tmp);
}
