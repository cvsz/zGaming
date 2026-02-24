#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 30] WALLET – Ledger / Reconciliation / Safety"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"

mkdir -p "$BACKEND"/{wallet,db,api}

# ============================================================
# 1. Wallet Ledger Schema (append-safe)
# ============================================================

cat > "$BACKEND/db/wallet.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS wallets (
  user_id BIGINT PRIMARY KEY,
  balance DECIMAL(18,6) NOT NULL DEFAULT 0,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS wallet_ledger (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  direction ENUM('debit','credit') NOT NULL,
  amount DECIMAL(18,6) NOT NULL,
  ref_type VARCHAR(32) NOT NULL,
  ref_id VARCHAR(64) NOT NULL,
  provider VARCHAR(32),
  balance_after DECIMAL(18,6),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_ref (ref_type, ref_id)
);
SQL

# ============================================================
# 2. Wallet Service (ACID + Lock)
# ============================================================

cat > "$BACKEND/wallet/WalletService.php" <<'PHP'
<?php
final class WalletService {

  public static function ensureUser(int $userId): void {
    $db = Database::conn();
    $db->prepare(
      "INSERT IGNORE INTO wallets (user_id, balance) VALUES (?, 0)"
    )->execute([$userId]);
  }

  public static function balance(int $userId): float {
    self::ensureUser($userId);
    $db = Database::conn();
    $stmt = $db->prepare("SELECT balance FROM wallets WHERE user_id=?");
    $stmt->execute([$userId]);
    return (float)$stmt->fetchColumn();
  }

  public static function apply(
    int $userId,
    string $direction,
    float $amount,
    string $refType,
    string $refId,
    ?string $provider = null
  ): void {
    $db = Database::conn();
    $db->beginTransaction();

    try {
      self::ensureUser($userId);

      // lock row
      $stmt = $db->prepare("SELECT balance FROM wallets WHERE user_id=? FOR UPDATE");
      $stmt->execute([$userId]);
      $balance = (float)$stmt->fetchColumn();

      if ($direction === 'debit' && $balance < $amount) {
        throw new RuntimeException('insufficient_balance');
      }

      $newBalance = $direction === 'credit'
        ? $balance + $amount
        : $balance - $amount;

      $db->prepare(
        "UPDATE wallets SET balance=? WHERE user_id=?"
      )->execute([$newBalance, $userId]);

      $db->prepare(
        "INSERT INTO wallet_ledger
          (user_id, direction, amount, ref_type, ref_id, provider, balance_after)
         VALUES (?,?,?,?,?,?,?)"
      )->execute([
        $userId,
        $direction,
        $amount,
        $refType,
        $refId,
        $provider,
        $newBalance
      ]);

      $db->commit();
    } catch (Throwable $e) {
      $db->rollBack();
      throw $e;
    }
  }
}
PHP

# ============================================================
# 3. Reconciliation Engine
# ============================================================

cat > "$BACKEND/wallet/ReconciliationService.php" <<'PHP'
<?php
final class ReconciliationService {

  public static function audit(int $userId): array {
    $db = Database::conn();

    $stmt = $db->prepare("
      SELECT COALESCE(SUM(
        CASE direction
          WHEN 'credit' THEN amount
          ELSE -amount
        END
      ),0)
      FROM wallet_ledger
      WHERE user_id=?
    ");
    $stmt->execute([$userId]);
    $ledgerBalance = (float)$stmt->fetchColumn();

    $stmt = $db->prepare("SELECT balance FROM wallets WHERE user_id=?");
    $stmt->execute([$userId]);
    $walletBalance = (float)$stmt->fetchColumn();

    return [
      'wallet_balance' => $walletBalance,
      'ledger_balance' => $ledgerBalance,
      'match' => abs($walletBalance - $ledgerBalance) < 0.0001
    ];
  }
}
PHP

# ============================================================
# 4. Admin API – Balance / Reconcile
# ============================================================

cat > "$BACKEND/api/admin-wallet.php" <<'PHP'
<?php
require_once __DIR__ . '/../core/Bootstrap.php';
require_once __DIR__ . '/../wallet/WalletService.php';
require_once __DIR__ . '/../wallet/ReconciliationService.php';

$userId = (int)($_GET['user_id'] ?? 0);
if (!$userId) {
  http_response_code(400);
  echo json_encode(['error' => 'missing_user']);
  exit;
}

echo json_encode([
  'balance' => WalletService::balance($userId),
  'audit'   => ReconciliationService::audit($userId)
]);
PHP

# ============================================================
# 5. Chaos Simulation (double callback / retry)
# ============================================================

cat > "$BACKEND/wallet/ChaosSimulator.php" <<'PHP'
<?php
final class ChaosSimulator {

  public static function doubleCredit(int $userId, float $amount): void {
    WalletService::apply($userId, 'credit', $amount, 'chaos', 'dup-test', 'test');
    WalletService::apply($userId, 'credit', $amount, 'chaos', 'dup-test', 'test');
  }
}
PHP

# ============================================================
# 6. Documentation
# ============================================================

cat > "$BACKEND/wallet/README.md" <<'MD'
# Wallet Architecture

## Model
- wallets = current balance
- wallet_ledger = immutable event log

## Guarantees
- ACID transaction
- Row-level locking
- Idempotent via (ref_type, ref_id)
- Double callback safe

## Reconciliation
ledger sum must equal wallet balance

## Chaos
Duplicate callbacks will fail on unique constraint
MD

echo "✅ PHASE 30 COMPLETE – Wallet core ready"