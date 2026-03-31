#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

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
  prev_hash CHAR(64) NOT NULL,
  hash CHAR(64) NOT NULL,
  balance_after DECIMAL(18,6),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_ref (user_id, ref_type, ref_id),
  KEY idx_user_created (user_id, created_at)
);

DELIMITER $$

DROP TRIGGER IF EXISTS wallet_ledger_immutable_update$$
CREATE TRIGGER wallet_ledger_immutable_update
BEFORE UPDATE ON wallet_ledger
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'wallet_ledger is immutable';
END$$

DROP TRIGGER IF EXISTS wallet_ledger_immutable_delete$$
CREATE TRIGGER wallet_ledger_immutable_delete
BEFORE DELETE ON wallet_ledger
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'wallet_ledger is immutable';
END$$

DELIMITER ;
SQL

# ============================================================
# 2. Wallet Service (ACID + Lock)
# ============================================================

cat > "$BACKEND/wallet/WalletService.php" <<'PHP'
<?php
use PDOException;

final class WalletService {
  private const SCALE = 6;
  private const MAX_RETRIES = 3;

  public static function ensureUser(int $userId): void {
    $db = Database::conn();
    $db->prepare(
      "INSERT IGNORE INTO wallets (user_id, balance) VALUES (?, 0)"
    )->execute([$userId]);
  }

  private static function normalizeAmount(string $amount): string {
    $amount = trim($amount);
    if (!preg_match('/^\d+(?:\.\d{1,6})?$/', $amount)) {
      throw new InvalidArgumentException('invalid_amount_format');
    }

    if (preg_match('/^0+(?:\.0+)?$/', $amount)) {
      throw new InvalidArgumentException('invalid_amount_non_positive');
    }

    if (str_contains($amount, '.')) {
      [$intPart, $decPart] = explode('.', $amount, 2);
      return $intPart . '.' . str_pad($decPart, self::SCALE, '0');
    }

    return $amount . '.' . str_repeat('0', self::SCALE);
  }

  private static function decimalCmp(string $left, string $right): int {
    return bccomp($left, $right, self::SCALE);
  }

  private static function decimalAdd(string $left, string $right): string {
    return bcadd($left, $right, self::SCALE);
  }

  private static function decimalSub(string $left, string $right): string {
    return bcsub($left, $right, self::SCALE);
  }

  private static function isDeadlock(PDOException $e): bool {
    $driverCode = $e->errorInfo[1] ?? null;
    return $driverCode === 1213 || $driverCode === 1205;
  }

  public static function balance(int $userId): string {
    self::ensureUser($userId);
    $db = Database::conn();
    $stmt = $db->prepare("SELECT balance FROM wallets WHERE user_id=?");
    $stmt->execute([$userId]);
    return (string)$stmt->fetchColumn();
  }

  public static function apply(
    int $userId,
    string $direction,
    string $amount,
    string $refType,
    string $refId,
    ?string $provider = null
  ): void {
    if (!in_array($direction, ['credit', 'debit'], true)) {
      throw new InvalidArgumentException('invalid_direction');
    }

    $normalizedAmount = self::normalizeAmount($amount);
    $db = Database::conn();

    for ($attempt = 1; $attempt <= self::MAX_RETRIES; $attempt++) {
      $db->exec("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE");
      $db->beginTransaction();

      try {
        self::ensureUser($userId);

        $ledgerLock = $db->prepare(
          "SELECT id
             FROM wallet_ledger
            WHERE user_id=? AND ref_type=? AND ref_id=?
            LIMIT 1
            FOR UPDATE"
        );
        $ledgerLock->execute([$userId, $refType, $refId]);

        if ($ledgerLock->fetchColumn()) {
          $db->commit();
          return;
        }

        $stmt = $db->prepare("SELECT balance FROM wallets WHERE user_id=? FOR UPDATE");
        $stmt->execute([$userId]);
        $balance = (string)$stmt->fetchColumn();

        if ($direction === 'debit' && self::decimalCmp($balance, $normalizedAmount) < 0) {
          throw new RuntimeException('insufficient_balance');
        }

        $newBalance = $direction === 'credit'
          ? self::decimalAdd($balance, $normalizedAmount)
          : self::decimalSub($balance, $normalizedAmount);

        $stmt = $db->prepare(
          "SELECT hash
             FROM wallet_ledger
            WHERE user_id=?
            ORDER BY id DESC
            LIMIT 1
            FOR UPDATE"
        );
        $stmt->execute([$userId]);
        $prevHash = (string)($stmt->fetchColumn() ?: str_repeat('0', 64));

        $entryPayload = implode('|', [
          $userId,
          $direction,
          $normalizedAmount,
          $refType,
          $refId,
          (string)($provider ?? ''),
          $newBalance,
          $prevHash
        ]);
        $hash = hash('sha256', $entryPayload);

        $db->prepare(
          "UPDATE wallets SET balance=? WHERE user_id=?"
        )->execute([$newBalance, $userId]);

        $db->prepare(
          "INSERT INTO wallet_ledger
            (user_id, direction, amount, ref_type, ref_id, provider, prev_hash, hash, balance_after)
           VALUES (?,?,?,?,?,?,?,?,?)"
        )->execute([
          $userId,
          $direction,
          $normalizedAmount,
          $refType,
          $refId,
          $provider,
          $prevHash,
          $hash,
          $newBalance
        ]);

        $db->commit();
        return;
      } catch (PDOException $e) {
        if ($db->inTransaction()) {
          $db->rollBack();
        }

        if ($attempt < self::MAX_RETRIES && self::isDeadlock($e)) {
          usleep(50000);
          continue;
        }

        throw $e;
      } catch (Throwable $e) {
        if ($db->inTransaction()) {
          $db->rollBack();
        }
        throw $e;
      }
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

  public static function duplicateCreditReplay(int $userId, string $amount): void {
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
- Idempotent via (user_id, ref_type, ref_id) before balance update
- Decimal-safe arithmetic via BCMath
- Deadlock retry and serializable transaction isolation
- Tamper-evident chain (`prev_hash` + `hash`) and immutable ledger triggers

## Reconciliation
ledger sum must equal wallet balance

## Chaos
Duplicate callback replay should be no-op on second attempt
MD

echo "✅ PHASE 30 COMPLETE – Wallet core ready"
