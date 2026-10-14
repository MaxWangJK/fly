<?php
declare(strict_types=1);

namespace FlyWeb;

use PDO;
use RuntimeException;
use Throwable;

final class Config
{
    public static function value(string $key): string
    {
        return trim((string) (getenv($key) ?: ''));
    }

    public static function baseUrl(): string
    {
        return rtrim(self::value('FLY_BASE_URL') ?: 'http://localhost:8080', '/');
    }

    public static function catalog(): array
    {
        return require __DIR__ . '/catalog.php';
    }

    public static function paymentReady(): bool
    {
        // Checkout stays disabled until a verified payment adapter is implemented.
        return false;
    }

    public static function issuerReady(): bool
    {
        return self::value('FLY_ISSUER_PRIVATE_KEY_FILE') !== ''
            && is_readable(self::value('FLY_ISSUER_PRIVATE_KEY_FILE'))
            && is_readable(self::issuerPublicPath());
    }

    public static function issuerPublicPath(): string
    {
        return self::value('FLY_ISSUER_PUBLIC_KEY_FILE') ?: __DIR__ . '/../issuer_public_key.txt';
    }
}

final class Database
{
    public static function connect(): PDO
    {
        $path = Config::value('FLY_DB_PATH') ?: __DIR__ . '/../var/fly.sqlite';
        $dir = dirname($path);
        if (!is_dir($dir) && !mkdir($dir, 0700, true) && !is_dir($dir)) {
            throw new RuntimeException('无法创建数据库目录');
        }
        $db = new PDO('sqlite:' . $path, null, null, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);
        $db->exec('PRAGMA foreign_keys = ON');
        $db->exec('PRAGMA busy_timeout = 5000');
        $db->exec('CREATE TABLE IF NOT EXISTS orders (
            id TEXT PRIMARY KEY, user_id TEXT NOT NULL, sku TEXT NOT NULL,
            amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
            modules_json TEXT NOT NULL, status TEXT NOT NULL CHECK (status IN (\'pending\', \'paid\')),
            payment_reference TEXT UNIQUE, created_at TEXT NOT NULL, paid_at TEXT
        )');
        $db->exec('CREATE INDEX IF NOT EXISTS orders_user_status ON orders(user_id, status)');
        $db->exec('CREATE TABLE IF NOT EXISTS activations (
            id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL,
            machine_code TEXT NOT NULL, sku TEXT NOT NULL, token TEXT NOT NULL,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
            UNIQUE(user_id, machine_code)
        )');
        return $db;
    }
}

final class Auth
{
    public static function userId(): ?string
    {
        // Only a verified, server-side identity callback may establish this session.
        $id = $_SESSION['fly_verified_user_id'] ?? null;
        return is_string($id) && preg_match('/^[A-Za-z0-9_-]{8,128}$/D', $id) ? $id : null;
    }
}

final class Orders
{
    public static function create(PDO $db, string $userId, string $sku): array
    {
        $plan = Config::catalog()[$sku] ?? null;
        if ($plan === null || $plan['price_cents'] < 1 || $plan['price_cents'] > 10000000000) {
            throw new RuntimeException('此方案尚未开放购买');
        }
        if (self::paidPlan($db, $userId) !== null) {
            throw new RuntimeException('此账户已有永久授权，升级方案开放后再购买其他模块');
        }
        $id = 'FLY' . gmdate('YmdHis') . strtoupper(bin2hex(random_bytes(6)));
        $order = [
            'id' => $id, 'user_id' => $userId, 'sku' => $sku,
            'amount_cents' => $plan['price_cents'],
            'modules_json' => json_encode($plan['modules'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
        ];
        $stmt = $db->prepare('INSERT INTO orders (id,user_id,sku,amount_cents,modules_json,status,created_at) VALUES (?,?,?,?,?,\'pending\',?)');
        $stmt->execute([$id, $userId, $sku, $order['amount_cents'], $order['modules_json'], gmdate('c')]);
        return $order;
    }

    public static function paidPlan(PDO $db, string $userId): ?array
    {
        $stmt = $db->prepare('SELECT sku,modules_json FROM orders WHERE user_id = ? AND status = \'paid\' ORDER BY paid_at DESC');
        $stmt->execute([$userId]);
        $catalog = Config::catalog();
        $best = null;
        foreach ($stmt as $row) {
            if (!isset($catalog[$row['sku']])) {
                continue;
            }
            if ($best === null || $catalog[$row['sku']]['rank'] > $catalog[$best['sku']]['rank']) {
                $best = $row;
            }
        }
        return $best;
    }

}

final class Licenses
{
    private static function b64(string $bytes): string
    {
        return rtrim(strtr(base64_encode($bytes), '+/', '-_'), '=');
    }

    public static function issue(string $machine, string $sku, array $modules): string
    {
        if (!Config::issuerReady()) {
            throw new RuntimeException('授权签发服务尚未配置');
        }
        $pem = (string) file_get_contents(Config::value('FLY_ISSUER_PRIVATE_KEY_FILE'));
        $der = base64_decode(preg_replace('/-----[^-]+-----|\s+/', '', $pem), true);
        $prefix = hex2bin('302e020100300506032b657004220420');
        if ($der === false || strlen($der) !== 48 || !str_starts_with($der, $prefix)) {
            throw new RuntimeException('授权私钥格式错误：需要 Ed25519 PKCS#8');
        }
        $keyPair = sodium_crypto_sign_seed_keypair(substr($der, 16, 32));
        $public = sodium_crypto_sign_publickey($keyPair);
        $expected = trim((string) file_get_contents(Config::issuerPublicPath()));
        if (!hash_equals($expected, self::b64($public))) {
            throw new RuntimeException('授权私钥与桌面版公钥不匹配');
        }
        $payload = json_encode([
            'machineCode' => $machine,
            'issuedAt' => gmdate('Y-m-d\TH:i:s\Z'),
            'expiresAt' => '9999-12-31T23:59:59Z',
            'licenseVersion' => 1,
            'nonce' => bin2hex(random_bytes(16)),
            'sku' => $sku,
            'modules' => $modules,
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        $signature = sodium_crypto_sign_detached($payload, sodium_crypto_sign_secretkey($keyPair));
        return self::b64($payload) . '.' . self::b64($signature);
    }

    public static function activate(PDO $db, string $userId, string $machine): array
    {
        $machine = strtoupper(trim($machine));
        if (!preg_match('/^[0-9A-F]{64}$/D', $machine)) {
            throw new RuntimeException('请输入完整的 64 位设备码');
        }
        $db->exec('BEGIN IMMEDIATE');
        try {
            $plan = Orders::paidPlan($db, $userId);
            if ($plan === null) {
                throw new RuntimeException('请先购买授权');
            }
            $stmt = $db->prepare('SELECT * FROM activations WHERE user_id = ? AND machine_code = ?');
            $stmt->execute([$userId, $machine]);
            $existing = $stmt->fetch();
            if ($existing && $existing['sku'] === $plan['sku']) {
                $db->commit();
                return $existing;
            }
            if (!$existing) {
                $stmt = $db->prepare('SELECT COUNT(*) FROM activations WHERE user_id = ?');
                $stmt->execute([$userId]);
                if ((int) $stmt->fetchColumn() >= 3) {
                    throw new RuntimeException('已达到 3 台设备上限，请联系售后处理换机');
                }
            }
            $token = self::issue($machine, $plan['sku'], json_decode($plan['modules_json'], true, 512, JSON_THROW_ON_ERROR));
            $now = gmdate('c');
            if ($existing) {
                $stmt = $db->prepare('UPDATE activations SET sku = ?, token = ?, updated_at = ? WHERE id = ?');
                $stmt->execute([$plan['sku'], $token, $now, $existing['id']]);
            } else {
                $stmt = $db->prepare('INSERT INTO activations (user_id,machine_code,sku,token,created_at,updated_at) VALUES (?,?,?,?,?,?)');
                $stmt->execute([$userId, $machine, $plan['sku'], $token, $now, $now]);
            }
            $db->commit();
            return ['machine_code' => $machine, 'sku' => $plan['sku'], 'token' => $token];
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
    }
}

function e(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
