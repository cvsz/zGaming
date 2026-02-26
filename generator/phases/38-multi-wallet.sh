#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail

echo "[PHASE 38] MULTI-WALLET PER PROVIDER"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"

# Ensure required directories exist
mkdir -p \
  "$BACKEND"/{wallet,db,core} \
  "$BACKEND/api/admin"

# ============================================================
# 1. Wallet per Provider Schema
# ============================================================

cat > "$BACKEND/db/multi_wallet.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS wallets (
  user_id BIGINT NOT NULL,
  provider VARCHAR(32) NOT NULL,
  currency CHAR(3) NOT NULL,
  balance DECIMAL(18,8) NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, provider, currency)
);

CREATE TABLE IF NOT EXISTS wallet_ledger (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  provider VARCHAR(32) NOT NULL,
  amount DECIMAL(18,8) NOT NULL,
  currency CHAR(3) NOT NULL,
  fx_rate DECIMAL(18,8) NOT NULL,
  base_amount DECIMAL(18,8) NOT NULL,
  ref VARCHAR(128) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_ref (user_id, provider, ref)
);
SQL

# ============================================================
# 2. Provider-Agnostic Wallet Domain Service
# ============================================================

cat > "$BACKEND/wallet/ProviderWallet.php" <<'PHP'
<?php
final class ProviderWallet {

  public static function credit(
    int $userId,
    string $provider,
    float $amount,
    string $currency,
    float $fxRate,
    string $ref,
    string $baseCurrency = 'USD'
  ): array {

    $db = Database::conn();
    $db->beginTransaction();

    try {
      // Idempotent ledger insert
      $db->prepare(
        "INSERT INTO wallet_ledger
         (user_id,provider,amount,currency,fx_rate,base_amount,ref)
         VALUES (?,?,?,?,?,?,?)"
      )->execute([
        $userId,
        $provider,
        $amount,
        $currency,
        $fxRate,
        $amount * $fxRate,
        $ref
      ]);

      // Provider wallet
      $db->prepare(
        "INSERT INTO wallets (user_id,provider,currency,balance)
         VALUES (?,?,?,0)
         ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)"
      )->execute([
        $userId,
        $provider,
        $currency,
        $amount
      ]);

      // Base accounting wallet
      $db->prepare(
        "INSERT INTO wallets (user_id,provider,currency,balance)
         VALUES (?,?,?,0)
         ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)"
      )->execute([
        $userId,
        '__BASE__',
        $baseCurrency,
        $amount * $fxRate
      ]);

      $bal = $db->prepare(
        "SELECT balance FROM wallets
         WHERE user_id=? AND provider=? AND currency=?"
      );
      $bal->execute([$userId, $provider, $currency]);

      $db->commit();

      return [
        'provider' => $provider,
        'currency' => $currency,
        'balance'  => (float)$bal->fetchColumn()
      ];

    } catch (Throwable $e) {
      $db->rollBack();
      throw $e;
    }
  }

  public static function getAll(int $userId): array {
    $stmt = Database::conn()->prepare(
      "SELECT provider, currency, balance
       FROM wallets WHERE user_id=?"
    );
    $stmt->execute([$userId]);
    return $stmt->fetchAll();
  }
}
PHP

# ============================================================
# 3. Provider Wallet Adapter (for callbacks)
# ============================================================

cat > "$BACKEND/wallet/ProviderWalletAdapter.php" <<'PHP'
<?php
final class ProviderWalletAdapter {

  public static function credit(
    int $userId,
    string $provider,
    float $amount,
    string $currency,
    string $ref
  ): array {
    $base = getenv('BASE_CURRENCY') ?: 'USD';
    $fx   = FX::rate($currency, $base);

    return ProviderWallet::credit(
      $userId,
      $provider,
      $amount,
      $currency,
      $fx,
      $ref,
      $base
    );
  }
}
PHP

# ============================================================
# 4. Admin API – View Multi-Wallet Balances
# ============================================================

cat > "$BACKEND/api/admin/wallets.php" <<'PHP'
<?php
require_once __DIR__ . '/../../core/Bootstrap.php';

Auth::requireRole('admin');

$userId = (int)($_GET['user'] ?? 0);
echo json_encode(ProviderWallet::getAll($userId));
PHP

# ============================================================
# 5. Documentation
# ============================================================

cat > "$BACKEND/wallet/MULTI_WALLET.md" <<'MD'
# Multi-Wallet per Provider

## Model
(user_id, provider, currency) → balance

## Ledger
- Idempotent by (user, provider, ref)
- FX snapshot stored per transaction

## Accounting
- Provider wallet: gameplay balances
- __BASE__ wallet: finance / P&L

## Notes
- Negative balances are allowed by design
- Enforcement belongs to business rules
MD

echo "✅ PHASE 38 COMPLETE – Multi-wallet per provider (spec-correct)"
