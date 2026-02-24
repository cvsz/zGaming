#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 50] PROVIDER CALLBACKS – Pragmatic Play / PG Soft"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"

mkdir -p "$BACKEND"/{providers,api/callback,core,db}

# ============================================================
# 1. Idempotency Table (กัน double callback)
# ============================================================

cat > "$BACKEND/db/callbacks.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS provider_callbacks (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  provider VARCHAR(32) NOT NULL,
  external_txn VARCHAR(128) NOT NULL,
  processed TINYINT(1) DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_provider_txn (provider, external_txn)
);
SQL

# ============================================================
# 2. Signature Verification (Pragmatic / PG)
# ============================================================

cat > "$BACKEND/core/ProviderSignature.php" <<'PHP'
<?php
final class ProviderSignature {

  public static function verifyPragmatic(array $data, string $secret): bool {
    $sign = $data['signature'] ?? '';
    unset($data['signature']);
    ksort($data);
    $base = http_build_query($data);
    $calc = hash_hmac('sha256', $base, $secret);
    return hash_equals($calc, $sign);
  }

  public static function verifyPG(array $data, string $secret): bool {
    $raw = json_encode($data, JSON_UNESCAPED_SLASHES);
    $calc = hash_hmac('sha256', $raw, $secret);
    return hash_equals($calc, $data['sign'] ?? '');
  }
}
PHP

# ============================================================
# 3. Wallet Atomic Handler
# ============================================================

cat > "$BACKEND/core/WalletAtomic.php" <<'PHP'
<?php
final class WalletAtomic {

  public static function apply(
    int $userId,
    float $amount,
    string $provider,
    string $externalTxn
  ): float {
    $db = Database::conn();
    $db->beginTransaction();

    try {
      $stmt = $db->prepare(
        "INSERT INTO provider_callbacks (provider, external_txn, processed)
         VALUES (?,?,0)"
      );
      $stmt->execute([$provider, $externalTxn]);

      $db->prepare(
        "UPDATE wallets SET balance = balance + ? WHERE user_id=?"
      )->execute([$amount, $userId]);

      $bal = $db->query(
        "SELECT balance FROM wallets WHERE user_id=$userId"
      )->fetchColumn();

      $db->prepare(
        "UPDATE provider_callbacks SET processed=1
         WHERE provider=? AND external_txn=?"
      )->execute([$provider,$externalTxn]);

      $db->commit();
      return (float)$bal;

    } catch (Throwable $e) {
      $db->rollBack();
      throw $e;
    }
  }
}
PHP

# ============================================================
# 4. Pragmatic Callback Endpoint
# ============================================================

cat > "$BACKEND/api/callback/pragmatic.php" <<'PHP'
<?php
require_once __DIR__ . '/../../core/Bootstrap.php';
require_once __DIR__ . '/../../core/ProviderSignature.php';
require_once __DIR__ . '/../../core/WalletAtomic.php';

$data = $_POST;
$secret = getenv('PRAGMATIC_SECRET');

if (!ProviderSignature::verifyPragmatic($data, $secret)) {
  http_response_code(403);
  echo json_encode(['error'=>'bad_signature']);
  exit;
}

$userId = (int)$data['user_id'];
$amount = (float)$data['amount'];
$txn    = $data['transaction_id'];

try {
  $bal = WalletAtomic::apply($userId, $amount, 'pragmatic', $txn);
  echo json_encode(['status'=>'ok','balance'=>$bal]);
} catch (Throwable $e) {
  if (str_contains($e->getMessage(),'uniq_provider_txn')) {
    echo json_encode(['status'=>'duplicate']);
  } else {
    http_response_code(500);
    echo json_encode(['error'=>'wallet_error']);
  }
}
PHP

# ============================================================
# 5. PG Soft Callback Endpoint
# ============================================================

cat > "$BACKEND/api/callback/pgsoft.php" <<'PHP'
<?php
require_once __DIR__ . '/../../core/Bootstrap.php';
require_once __DIR__ . '/../../core/ProviderSignature.php';
require_once __DIR__ . '/../../core/WalletAtomic.php';

$raw = json_decode(file_get_contents('php://input'), true);
$secret = getenv('PGSOFT_SECRET');

if (!ProviderSignature::verifyPG($raw, $secret)) {
  http_response_code(403);
  echo json_encode(['error'=>'bad_signature']);
  exit;
}

$userId = (int)$raw['playerId'];
$amount = (float)$raw['winAmount'];
$txn    = $raw['roundId'];

try {
  $bal = WalletAtomic::apply($userId, $amount, 'pgsoft', $txn);
  echo json_encode(['code'=>0,'balance'=>$bal]);
} catch (Throwable $e) {
  if (str_contains($e->getMessage(),'uniq_provider_txn')) {
    echo json_encode(['code'=>0,'duplicate'=>true]);
  } else {
    http_response_code(500);
    echo json_encode(['code'=>500]);
  }
}
PHP

# ============================================================
# 6. Docs
# ============================================================

cat > "$BACKEND/providers/CALLBACKS.md" <<'MD'
# Provider Callbacks

## Pragmatic
POST /api/callback/pragmatic.php
- HMAC SHA256 query-string
- Idempotent by transaction_id

## PG Soft
POST /api/callback/pgsoft.php
- JSON body
- HMAC SHA256 raw body
- Idempotent by roundId
MD

echo "✅ PHASE 50 COMPLETE – Provider callbacks hardened"