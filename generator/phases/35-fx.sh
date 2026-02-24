#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 35] MULTI-CURRENCY / FX ENGINE"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"

mkdir -p "$BACKEND"/{fx,db,core,wallet}

# ============================================================
# 1. Currency & FX Schema
# ============================================================

cat > "$BACKEND/db/fx.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS currencies (
  code CHAR(3) PRIMARY KEY,
  precision TINYINT NOT NULL DEFAULT 2,
  enabled TINYINT(1) DEFAULT 1
);

INSERT IGNORE INTO currencies (code,precision) VALUES
('USD',2),('EUR',2),('THB',2),('IDR',0),('VND',0);

CREATE TABLE IF NOT EXISTS fx_rates (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  base CHAR(3) NOT NULL,
  quote CHAR(3) NOT NULL,
  rate DECIMAL(18,8) NOT NULL,
  source VARCHAR(32) NOT NULL,
  valid_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_fx (base,quote,valid_from)
);

CREATE TABLE IF NOT EXISTS wallet_balances (
  user_id BIGINT,
  currency CHAR(3),
  balance DECIMAL(18,8) NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id,currency)
);

CREATE TABLE IF NOT EXISTS wallet_ledger (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT,
  amount DECIMAL(18,8),
  currency CHAR(3),
  fx_rate DECIMAL(18,8),
  base_amount DECIMAL(18,8),
  provider VARCHAR(32),
  ref VARCHAR(128),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQL

# ============================================================
# 2. FX Rate Resolver (Immutable Snapshot)
# ============================================================

cat > "$BACKEND/fx/FX.php" <<'PHP'
<?php
final class FX {

  public static function rate(string $base, string $quote): float {
    if ($base === $quote) return 1.0;

    $db = Database::conn();
    $stmt = $db->prepare(
      "SELECT rate FROM fx_rates
       WHERE base=? AND quote=?
       ORDER BY valid_from DESC LIMIT 1"
    );
    $stmt->execute([$base,$quote]);
    $rate = $stmt->fetchColumn();

    if (!$rate) {
      throw new RuntimeException("fx_rate_missing");
    }
    return (float)$rate;
  }
}
PHP

# ============================================================
# 3. Wallet FX-Aware Atomic Apply
# ============================================================

cat > "$BACKEND/wallet/WalletFX.php" <<'PHP'
<?php
final class WalletFX {

  // baseCurrency = platform accounting currency (e.g. USD)
  public static function apply(
    int $userId,
    float $amount,
    string $currency,
    string $provider,
    string $ref,
    string $baseCurrency = 'USD'
  ): array {
    $db = Database::conn();
    $db->beginTransaction();

    try {
      $rate = FX::rate($currency, $baseCurrency);
      $baseAmount = round($amount * $rate, 8);

      $db->prepare(
        "INSERT INTO wallet_balances (user_id,currency,balance)
         VALUES (?,?,0)
         ON DUPLICATE KEY UPDATE balance = balance + ?"
      )->execute([$userId,$currency,$amount,$amount]);

      $db->prepare(
        "INSERT INTO wallet_balances (user_id,currency,balance)
         VALUES (?,?,0)
         ON DUPLICATE KEY UPDATE balance = balance + ?"
      )->execute([$userId,$baseCurrency,$baseAmount,$baseAmount]);

      $db->prepare(
        "INSERT INTO wallet_ledger
         (user_id,amount,currency,fx_rate,base_amount,provider,ref)
         VALUES (?,?,?,?,?,?,?)"
      )->execute([
        $userId,$amount,$currency,$rate,$baseAmount,$provider,$ref
      ]);

      $db->commit();

      return [
        'currency'=>$currency,
        'amount'=>$amount,
        'fx_rate'=>$rate,
        'base_amount'=>$baseAmount
      ];

    } catch (Throwable $e) {
      $db->rollBack();
      throw $e;
    }
  }
}
PHP

# ============================================================
# 4. Provider Callback FX Integration
# ============================================================

cat > "$BACKEND/wallet/ProviderWalletAdapter.php" <<'PHP'
<?php
final class ProviderWalletAdapter {

  public static function credit(
    int $userId,
    float $amount,
    string $currency,
    string $provider,
    string $ref
  ): array {
    return WalletFX::apply(
      $userId,
      $amount,
      $currency,
      $provider,
      $ref,
      getenv('BASE_CURRENCY') ?: 'USD'
    );
  }
}
PHP

# ============================================================
# 5. FX Seeder (Manual / Ops Controlled)
# ============================================================

cat > "$BACKEND/fx/seed.php" <<'PHP'
<?php
require_once __DIR__ . '/../core/Bootstrap.php';

$db = Database::conn();

$rates = [
  ['USD','THB',36.50],
  ['USD','EUR',0.92],
  ['USD','IDR',15500],
  ['USD','VND',24500],
];

foreach ($rates as [$b,$q,$r]) {
  $db->prepare(
    "INSERT INTO fx_rates (base,quote,rate,source)
     VALUES (?,?,?,'manual')"
  )->execute([$b,$q,$r]);
}

echo "FX seeded\n";
PHP

# ============================================================
# 6. Documentation
# ============================================================

cat > "$BACKEND/fx/README.md" <<'MD'
# Multi-Currency / FX Engine

## Principles
- Wallet keeps original currency
- Platform accounting in BASE_CURRENCY
- FX rate snapshot stored per transaction
- Ledger is immutable

## Why
- Audit / regulator safe
- Provider currency mismatch safe
- No retroactive FX mutation

## Flow
Provider amount (local)
 -> FX snapshot
 -> Ledger
 -> Base accounting
MD

echo "✅ PHASE 35 COMPLETE – Multi-currency FX ready"