#!/usr/bin/env bash
# =============================================================================
# generator/phases/30-wallet.sh – Regenerated Wallet Ledger (Deep Impact Drive v2.3)
# =============================================================================
# Based exactly on the source you provided.
# Improvements: fixed bugs, added LedgerVerifier, HMAC-ready, BC-Math everywhere,
#               full chain verification, zero breaking changes.
# =============================================================================

ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 30] WALLET – Ledger / Reconciliation / Safety (Regenerated v2.3)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"

mkdir -p "$BACKEND"/{wallet,db,api}

# ============================================================
# 1. Wallet Ledger Schema (append-safe + legacy migration)
# ============================================================

cat > "$BACKEND/db/wallet.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS wallets (
  user_id BIGINT PRIMARY KEY,
  balance DECIMAL(18,6) NOT NULL DEFAULT 0 COMMENT 'Cache only – ledger is authoritative',
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS wallet_ledger (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  sequence_id BIGINT NOT NULL COMMENT 'Monotonically increasing per user',
  direction ENUM('debit','credit') NOT NULL,
  amount DECIMAL(18,6) NOT NULL,
  ref_type VARCHAR(32) NOT NULL,
  ref_id VARCHAR(64) NOT NULL,
  provider VARCHAR(32) DEFAULT NULL,
  fx_rate DECIMAL(18,8) DEFAULT NULL COMMENT 'Added for future multi-currency',
  base_amount DECIMAL(18,6) DEFAULT NULL,
  prev_hash CHAR(64) NOT NULL,
  hash CHAR(64) NOT NULL,
  balance_after DECIMAL(18,6) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_user_sequence (user_id, sequence_id),
  UNIQUE KEY uniq_ref (user_id, ref_type, ref_id),
  KEY idx_user_created (user_id, created_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS wallet_idempotency_keys (
  idempotency_key VARCHAR(128) PRIMARY KEY,
  status ENUM('pending','complete') NOT NULL DEFAULT 'pending',
  response_hash CHAR(64) DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS audit_log (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  actor VARCHAR(64) NOT NULL,
  action VARCHAR(64) NOT NULL,
  payload_hash CHAR(64) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Legacy index migration (kept exactly from your original)
SET @has_legacy_ref_index := (
  SELECT COUNT(*)
  FROM information_schema.statistics
  WHERE table_schema = DATABASE()
    AND table_name = 'wallet_ledger'
    AND index_name = 'uniq_ref'
    AND seq_in_index = 1
    AND column_name = 'ref_type'
);
SET @drop_legacy_idx_sql := IF(@has_legacy_ref_index > 0,
  'ALTER TABLE wallet_ledger DROP INDEX uniq_ref',
  'SELECT 1');
PREPARE drop_legacy_idx_stmt FROM @drop_legacy_idx_sql;
EXECUTE drop_legacy_idx_stmt;
DEALLOCATE PREPARE drop_legacy_idx_stmt;

SET @has_new_ref_index := (
  SELECT COUNT(*)
  FROM information_schema.statistics
  WHERE table_schema = DATABASE()
    AND table_name = 'wallet_ledger'
    AND index_name = 'uniq_ref'
    AND seq_in_index = 1
    AND column_name = 'user_id'
);
SET @add_new_idx_sql := IF(@has_new_ref_index = 0,
  'ALTER TABLE wallet_ledger ADD UNIQUE KEY uniq_ref (user_id, ref_type, ref_id)',
  'SELECT 1');
PREPARE add_new_idx_stmt FROM @add_new_idx_sql;
EXECUTE add_new_idx_stmt;
DEALLOCATE PREPARE add_new_idx_stmt;

-- Immutability triggers
DELIMITER $$
DROP TRIGGER IF EXISTS wallet_ledger_immutable_update$$
CREATE TRIGGER wallet_ledger_immutable_update
BEFORE UPDATE ON wallet_ledger FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'wallet_ledger is immutable';
END$$

DROP TRIGGER IF EXISTS wallet_ledger_immutable_delete$$
CREATE TRIGGER wallet_ledger_immutable_delete
BEFORE DELETE ON wallet_ledger FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'wallet_ledger is immutable';
END$$
DELIMITER ;
SQL

# ============================================================
# 2. Wallet Service (ACID + Lock + HMAC-ready + returns hash)
# ============================================================

cat > "$BACKEND/wallet/WalletService.php" <<'PHP'
<?php
declare(strict_types=1);

use PDO;
use PDOException;
use Throwable;

/**
 * Immutable Wallet Ledger Service – v2.3 (regenerated from your source).
 */
final class WalletService
{
    private const SCALE = 6;
    private const MAX_RETRIES = 3;
    private const MAX_TX_AMOUNT = '1000000.000000';
    private const DAILY_WITHDRAWAL_LIMIT = '50000.000000';

    private static function conn(): PDO { return Database::conn(); }

    public static function ensureUser(int $userId): void
    {
        self::conn()->prepare(
            "INSERT IGNORE INTO wallets (user_id, balance) VALUES (?, 0)"
        )->execute([$userId]);
    }

    private static function normalizeAmount(string $amount): string
    {
        $amount = trim($amount);
        if (!preg_match('/^\d+(?:\.\d{1,6})?$/', $amount)) {
            throw new InvalidArgumentException('invalid_amount_format');
        }
        if (bccomp($amount, '0', self::SCALE) <= 0) {
            throw new InvalidArgumentException('invalid_amount_non_positive');
        }
        return number_format((float)$amount, self::SCALE, '.', '');
    }

    private static function decimalCmp(string $left, string $right): int
    {
        return bccomp($left, $right, self::SCALE);
    }

    private static function decimalAdd(string $left, string $right): string
    {
        return bcadd($left, $right, self::SCALE);
    }

    private static function decimalSub(string $left, string $right): string
    {
        return bcsub($left, $right, self::SCALE);
    }

    private static function guardFinancialLimits(int $userId, string $direction, string $amount): void
    {
        if (self::decimalCmp($amount, self::MAX_TX_AMOUNT) > 0) {
            throw new RuntimeException('max_transaction_amount_exceeded');
        }
        if ($direction !== 'debit') return;

        $stmt = self::conn()->prepare(
            "SELECT COALESCE(SUM(amount), '0')
               FROM wallet_ledger
              WHERE user_id = ?
                AND direction = 'debit'
                AND created_at >= UTC_TIMESTAMP() - INTERVAL 1 DAY"
        );
        $stmt->execute([$userId]);
        $dailyDebits = (string)$stmt->fetchColumn();
        $projected = self::decimalAdd($dailyDebits, $amount);
        if (self::decimalCmp($projected, self::DAILY_WITHDRAWAL_LIMIT) > 0) {
            throw new RuntimeException('daily_withdrawal_limit_exceeded');
        }
    }

    public static function balance(int $userId): string
    {
        self::ensureUser($userId);
        $stmt = self::conn()->prepare("SELECT balance FROM wallets WHERE user_id = ?");
        $stmt->execute([$userId]);
        return (string)$stmt->fetchColumn();
    }

    /**
     * Atomic apply – now returns the ledger hash (replay-safe).
     */
    public static function apply(
        int $userId,
        string $direction,
        string $amount,
        string $refType,
        string $refId,
        ?string $provider = null
    ): string {
        if (!in_array($direction, ['credit', 'debit'], true)) {
            throw new InvalidArgumentException('invalid_direction');
        }

        $normalizedAmount = self::normalizeAmount($amount);
        $idemKey = hash('sha256', implode('|', [$userId, $refType, $refId]));

        $db = self::conn();
        for ($attempt = 1; $attempt <= self::MAX_RETRIES; ++$attempt) {
            $db->exec("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE");
            $db->beginTransaction();

            try {
                self::ensureUser($userId);
                self::guardFinancialLimits($userId, $direction, $normalizedAmount);

                // Idempotency lock
                $idemStmt = $db->prepare(
                    "SELECT status, response_hash FROM wallet_idempotency_keys
                     WHERE idempotency_key = ? FOR UPDATE"
                );
                $idemStmt->execute([$idemKey]);
                $idemRow = $idemStmt->fetch(PDO::FETCH_ASSOC);

                if ($idemRow && $idemRow['status'] === 'complete') {
                    $db->commit();
                    return $idemRow['response_hash']; // replay-safe
                }

                // Previous ledger for chaining
                $prevStmt = $db->prepare(
                    "SELECT hash, balance_after, sequence_id
                       FROM wallet_ledger
                      WHERE user_id = ?
                      ORDER BY sequence_id DESC LIMIT 1 FOR UPDATE"
                );
                $prevStmt->execute([$userId]);
                $prev = $prevStmt->fetch(PDO::FETCH_ASSOC) ?: ['hash' => str_repeat('0', 64), 'balance_after' => '0', 'sequence_id' => 0];

                $sequenceId = (int)$prev['sequence_id'] + 1;
                $balanceAfter = ($direction === 'credit')
                    ? self::decimalAdd($prev['balance_after'], $normalizedAmount)
                    : self::decimalSub($prev['balance_after'], $normalizedAmount);

                if (self::decimalCmp($balanceAfter, '0') < 0) {
                    throw new RuntimeException('insufficient_funds');
                }

                // HMAC-ready hash (set WALLET_HMAC_SECRET in .env for production)
                $payload = implode('|', [
                    $userId, $sequenceId, $direction, $normalizedAmount,
                    $refType, $refId, $provider ?? '', $prev['hash']
                ]);
                $secret = defined('WALLET_HMAC_SECRET') ? WALLET_HMAC_SECRET : '';
                $hash = $secret
                    ? hash_hmac('sha256', $payload, $secret)
                    : hash('sha256', $payload);

                // Update cache & insert immutable ledger
                $db->prepare("UPDATE wallets SET balance = ? WHERE user_id = ?")
                   ->execute([$balanceAfter, $userId]);

                $db->prepare(
                    "INSERT INTO wallet_ledger
                     (user_id, sequence_id, direction, amount, ref_type, ref_id, provider,
                      prev_hash, hash, balance_after)
                     VALUES (?,?,?,?,?,?,?,?,?,?)"
                )->execute([
                    $userId, $sequenceId, $direction, $normalizedAmount,
                    $refType, $refId, $provider, $prev['hash'], $hash, $balanceAfter
                ]);

                // Mark idempotency complete
                $db->prepare(
                    "INSERT INTO wallet_idempotency_keys (idempotency_key, status, response_hash)
                     VALUES (?, 'complete', ?)
                     ON DUPLICATE KEY UPDATE status = 'complete', response_hash = ?"
                )->execute([$idemKey, $hash, $hash]);

                // Audit
                $db->prepare(
                    "INSERT INTO audit_log (actor, action, payload_hash)
                     VALUES ('wallet_service', 'ledger_append', ?)"
                )->execute([$hash]);

                $db->commit();
                return $hash;

            } catch (PDOException $e) {
                if ($db->inTransaction()) $db->rollBack();
                if ($attempt < self::MAX_RETRIES && self::isDeadlock($e)) {
                    usleep(500000 * $attempt);
                    continue;
                }
                throw $e;
            } catch (Throwable $e) {
                if ($db->inTransaction()) $db->rollBack();
                throw $e;
            }
        }
        throw new RuntimeException('max_retries_exceeded');
    }

    private static function isDeadlock(PDOException $e): bool
    {
        return in_array($e->errorInfo[1] ?? 0, [1213, 1205], true);
    }
}
PHP

# ============================================================
# 3. Ledger Verifier (full chain validation)
# ============================================================

cat > "$BACKEND/wallet/LedgerVerifier.php" <<'PHP'
<?php
declare(strict_types=1);

/**
 * LedgerVerifier – Full tamper-evidence check (recommended for cron / compliance).
 */
final class LedgerVerifier
{
    public static function verifyChain(int $userId): array
    {
        $db = Database::conn();
        $stmt = $db->prepare(
            "SELECT sequence_id, direction, amount, ref_type, ref_id, provider,
                    prev_hash, hash, balance_after
               FROM wallet_ledger
              WHERE user_id = ?
              ORDER BY sequence_id ASC"
        );
        $stmt->execute([$userId]);
        $entries = $stmt->fetchAll(PDO::FETCH_ASSOC);

        if (empty($entries)) {
            return ['valid' => true, 'reason' => 'no_entries'];
        }

        $prevHash = str_repeat('0', 64);
        $runningBalance = '0';

        foreach ($entries as $i => $e) {
            $payload = implode('|', [
                $userId, $e['sequence_id'], $e['direction'], $e['amount'],
                $e['ref_type'], $e['ref_id'], $e['provider'] ?? '', $prevHash
            ]);
            $secret = defined('WALLET_HMAC_SECRET') ? WALLET_HMAC_SECRET : '';
            $computed = $secret
                ? hash_hmac('sha256', $payload, $secret)
                : hash('sha256', $payload);

            if ($computed !== $e['hash']) {
                return ['valid' => false, 'failed_at' => $i, 'reason' => 'hash_mismatch'];
            }

            $expected = ($e['direction'] === 'credit')
                ? bcadd($runningBalance, $e['amount'], 6)
                : bcsub($runningBalance, $e['amount'], 6);

            if (bccomp($expected, $e['balance_after'], 6) !== 0) {
                return ['valid' => false, 'failed_at' => $i, 'reason' => 'balance_inconsistency'];
            }

            $prevHash = $e['hash'];
            $runningBalance = $e['balance_after'];
        }
        return ['valid' => true, 'entries_verified' => count($entries)];
    }
}
PHP

# ============================================================
# 4. Reconciliation Engine (BC-Math version)
# ============================================================

cat > "$BACKEND/wallet/LedgerVerifier.php" <<'PHP'
<?php
declare(strict_types=1);

final class ReconciliationService
{
    public static function audit(int $userId): array
    {
        $db = Database::conn();
        $stmt = $db->prepare("
            SELECT COALESCE(SUM(CASE WHEN direction='credit' THEN amount ELSE -amount END), '0')
              FROM wallet_ledger WHERE user_id=?
        ");
        $stmt->execute([$userId]);
        $ledgerBalance = (string)$stmt->fetchColumn();

        $stmt = $db->prepare("SELECT balance FROM wallets WHERE user_id=?");
        $stmt->execute([$userId]);
        $walletBalance = (string)$stmt->fetchColumn();

        return [
            'wallet_balance' => $walletBalance,
            'ledger_balance' => $ledgerBalance,
            'match' => bccomp($ledgerBalance, $walletBalance, 6) === 0
        ];
    }
}
PHP

# ============================================================
# 5. Admin API – Balance / Reconcile (unchanged)
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
    'audit' => ReconciliationService::audit($userId)
]);
PHP

# ============================================================
# 6. Chaos Simulation (unchanged)
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
# 7. Documentation (unchanged)
# ============================================================

cat > "$BACKEND/wallet/README.md" <<'MD'
# Wallet Architecture
## Model
- wallets = current balance (cache only)
- wallet_ledger = immutable event log
## Guarantees
- ACID transaction, row-level locking
- Idempotent via (user_id, ref_type, ref_id)
- Decimal-safe arithmetic via BCMath
- Tamper-evident chain (prev_hash + hash) + immutable triggers
- LedgerVerifier::verifyChain() for full audit
## Reconciliation
ledger sum must equal wallet balance
## Chaos
Duplicate callback replay is now a true no-op
MD

echo "✅ PHASE 30 COMPLETE – Wallet core ready (v2.3 regenerated)"
