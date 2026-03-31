#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

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
  callback_nonce VARCHAR(128) NOT NULL,
  callback_ts BIGINT NOT NULL,
  payload_hash CHAR(64) NOT NULL,
  processed TINYINT(1) DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_provider_txn (provider, external_txn),
  UNIQUE KEY uniq_provider_nonce (provider, callback_nonce)
);
SQL

# ============================================================
# 2. Signature Verification (Pragmatic / PG)
# ============================================================

cat > "$BACKEND/core/ProviderSignature.php" <<'PHP'
<?php
final class ProviderSignature {
  private const MAX_SKEW_MS = 300000;

  public static function verifyPragmatic(array $data, string $secret, string $rawBody): bool {
    $sign = $data['signature'] ?? '';
    $timestamp = isset($data['ts']) ? (int)$data['ts'] : 0;
    if (!self::validateTimestamp($timestamp)) {
      return false;
    }
    unset($data['signature']);
    ksort($data);
    $base = http_build_query($data);
    $calc = hash_hmac('sha256', $base . '.' . $rawBody, $secret);
    return hash_equals($calc, $sign);
  }

  public static function verifyPG(array $data, string $secret, string $rawBody): bool {
    $timestamp = isset($data['ts']) ? (int)$data['ts'] : 0;
    if (!self::validateTimestamp($timestamp)) {
      return false;
    }
    $calc = hash_hmac('sha256', $rawBody . '.' . $timestamp, $secret);
    return hash_equals($calc, $data['sign'] ?? '');
  }

  private static function validateTimestamp(int $timestampMs): bool {
    if ($timestampMs <= 0) {
      return false;
    }
    $nowMs = (int)floor(microtime(true) * 1000);
    return abs($nowMs - $timestampMs) <= self::MAX_SKEW_MS;
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
    string $externalTxn,
    string $nonce,
    int $callbackTs,
    string $payloadHash
  ): float {
    $db = Database::conn();
    $db->beginTransaction();

    try {
      $stmt = $db->prepare(
        "INSERT INTO provider_callbacks (provider, external_txn, processed)
         VALUES (?,?,?,?,?,0)"
      );
      $stmt->execute([$provider, $externalTxn, $nonce, $callbackTs, $payloadHash]);

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
$rawBody = file_get_contents('php://input') ?: '';
$secret = getenv('PRAGMATIC_SECRET');

if (!ProviderSignature::verifyPragmatic($data, $secret, $rawBody)) {
  http_response_code(403);
  echo json_encode(['error'=>'bad_signature']);
  exit;
}

$userId = (int)$data['user_id'];
$amount = (float)$data['amount'];
$txn    = $data['transaction_id'];
$nonce  = (string)($data['nonce'] ?? '');
$ts     = (int)($data['ts'] ?? 0);
$payloadHash = hash('sha256', $rawBody);
if ($nonce === '' || $ts <= 0) {
  http_response_code(400);
  echo json_encode(['error'=>'missing_nonce_or_ts']);
  exit;
}

try {
  $bal = WalletAtomic::apply($userId, $amount, 'pragmatic', $txn, $nonce, $ts, $payloadHash);
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

$rawBody = file_get_contents('php://input') ?: '';
$raw = json_decode($rawBody, true);
$secret = getenv('PGSOFT_SECRET');

if (!ProviderSignature::verifyPG($raw, $secret, $rawBody)) {
  http_response_code(403);
  echo json_encode(['error'=>'bad_signature']);
  exit;
}

$userId = (int)$raw['playerId'];
$amount = (float)$raw['winAmount'];
$txn    = $raw['roundId'];
$nonce  = (string)($raw['nonce'] ?? '');
$ts     = (int)($raw['ts'] ?? 0);
$payloadHash = hash('sha256', $rawBody);
if ($nonce === '' || $ts <= 0) {
  http_response_code(400);
  echo json_encode(['error'=>'missing_nonce_or_ts']);
  exit;
}

try {
  $bal = WalletAtomic::apply($userId, $amount, 'pgsoft', $txn, $nonce, $ts, $payloadHash);
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
