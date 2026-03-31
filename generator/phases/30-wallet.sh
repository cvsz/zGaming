#!/usr/bin/env bash
# =============================================================================
# generator/phases/30-wallet.sh – Regenerated Wallet Ledger (Deep Impact Drive)
# =============================================================================
# Author: zGaming Generator (regenerated per security audit)
# Version: 2.2 (2026-03)
# Purpose: Generate immutable, tamper-evident wallet ledger with enhanced
#          verification, signing readiness, and reconciliation support.
# =============================================================================

ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 30] WALLET – Ledger / Reconciliation / Safety (Regenerated v2.2)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"

mkdir -p "$BACKEND"/{wallet,db,api}

# ============================================================
# 1. Wallet Ledger Schema (append-only + immutable triggers)
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
  fx_rate DECIMAL(18,8) DEFAULT NULL COMMENT 'Snapshot for multi-currency',
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
# 2. Wallet Service (ACID, locking, idempotency, financial guards)
# ============================================================

cat > "$BACKEND/wallet/WalletService.php" <<'PHP'
<?php
declare(strict_types=1);

use PDO;
use PDOException;

/**
 * Immutable Wallet Ledger Service – Single source of truth for financial operations.
 * Regenerated v2.2 with enhanced verification and signing readiness.
 */
final class WalletService
{
    private const SCALE = 6;
    private const MAX_RETRIES = 3;
    private const MAX_TX_AMOUNT = '1000000.000000';
    private const DAILY_WITHDRAWAL_LIMIT = '50000.000000';

    private static function conn(): PDO
    {
        return Database::conn();
    }

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

    private static function guardFinancialLimits(int $userId, string $direction, string $amount): void
    {
        if (bccomp($amount, self::MAX_TX_AMOUNT, self::SCALE) > 0) {
            throw new RuntimeException('max_transaction_amount_exceeded');
        }
        if ($direction !== 'debit') {
            return;
        }

        $stmt = self::conn()->prepare(
            "SELECT COALESCE(SUM(amount), '0')
               FROM wallet_ledger
              WHERE user_id = ?
                AND direction = 'debit'
                AND created_at >= UTC_TIMESTAMP() - INTERVAL 1 DAY"
        );
        $stmt->execute([$userId]);
        $dailyDebits = (string)$stmt->fetchColumn();
        $projected = bcadd($dailyDebits, $amount, self::SCALE);
        if (bccomp($projected, self::DAILY_WITHDRAWAL_LIMIT, self::SCALE) > 0) {
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
     * Atomic ledger append with full replay protection and hash chaining.
     */
    public static function apply(
        int $userId,
        string $direction,
        string $amount,
        string $refType,
        string $refId,
        ?string $provider = null,
        ?string $fxRate = null,
        ?string $baseAmount = null
    ): string {
        if (!in_array($direction, ['credit', 'debit'], true)) {
            throw new InvalidArgumentException('invalid_direction');
        }

        $amount = self::normalizeAmount($amount);
        $idemKey = hash('sha256', $userId . '|' . $refType . '|' . $refId);

        $db = self::conn();
        for ($attempt = 1; $attempt <= self::MAX_RETRIES; ++$attempt) {
            $db->exec("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE");
            $db->beginTransaction();

            try {
                self::ensureUser($userId);
                self::guardFinancialLimits($userId, $direction, $amount);

                // Idempotency check (locked)
                $idemStmt = $db->prepare(
                    "SELECT status, response_hash
                       FROM wallet_idempotency_keys
                      WHERE idempotency_key = ? FOR UPDATE"
                );
                $idemStmt->execute([$idemKey]);
                $row = $idemStmt->fetch(PDO::FETCH_ASSOC);

                if ($row && $row['status'] === 'complete') {
                    $db->rollBack();
                    return $row['response_hash']; // Replay-safe response
                }

                // Acquire previous ledger row for chaining
                $prevStmt = $db->prepare(
                    "SELECT hash, balance_after, sequence_id
                       FROM wallet_ledger
                      WHERE user_id = ?
                      ORDER BY sequence_id DESC
                      LIMIT 1 FOR UPDATE"
                );
                $prevStmt->execute([$userId]);
                $prev = $prevStmt->fetch(PDO::FETCH_ASSOC) ?: ['hash' => '0', 'balance_after' => '0', 'sequence_id' => 0];

                $sequence = $prev['sequence_id'] + 1;
                $balanceAfter = ($direction === 'credit')
                    ? bcadd($prev['balance_after'], $amount, self::SCALE)
                    : bcsub($prev['balance_after'], $amount, self::SCALE);

                if (bccomp($balanceAfter, '0', self::SCALE) < 0) {
                    throw new RuntimeException('insufficient_funds');
                }

                // Compute hash (HMAC-ready – set WALLET_HMAC_SECRET in .env for production)
                $payload = $userId . '|' . $sequence . '|' . $direction . '|' . $amount . '|' .
                           $refType . '|' . $refId . '|' . ($provider ?? '') . '|' .
                           ($fxRate ?? '') . '|' . ($baseAmount ?? '') . '|' . $prev['hash'];
                $secret = defined('WALLET_HMAC_SECRET') ? WALLET_HMAC_SECRET : '';
                $hash = $secret
                    ? hash_hmac('sha256', $payload, $secret)
                    : hash('sha256', $payload);

                // Insert immutable ledger entry
                $insertStmt = $db->prepare(
                    "INSERT INTO wallet_ledger
                     (user_id, sequence_id, direction, amount, ref_type, ref_id, provider,
                      fx_rate, base_amount, prev_hash, hash, balance_after)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
                );
                $insertStmt->execute([
                    $userId, $sequence, $direction, $amount, $refType, $refId, $provider,
                    $fxRate, $baseAmount, $prev['hash'], $hash, $balanceAfter
                ]);

                // Update cache (non-authoritative)
                $db->prepare(
                    "UPDATE wallets SET balance = ? WHERE user_id = ?"
                )->execute([$balanceAfter, $userId]);

                // Audit log
                $db->prepare(
                    "INSERT INTO audit_log (actor, action, payload_hash)
                     VALUES ('wallet_service', 'ledger_append', ?)"
                )->execute([$hash]);

                // Mark idempotency complete
                $db->prepare(
                    "INSERT INTO wallet_idempotency_keys (idempotency_key, status, response_hash)
                     VALUES (?, 'complete', ?)
                     ON DUPLICATE KEY UPDATE status = 'complete', response_hash = ?"
                )->execute([$idemKey, $hash, $hash]);

                $db->commit();
                return $hash;

            } catch (PDOException $e) {
                $db->rollBack();
                if (self::isDeadlock($e) && $attempt < self::MAX_RETRIES) {
                    usleep(500000 * $attempt); // back-off
                    continue;
                }
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
# 3. Ledger Verifier (tamper-evidence & chain validation)
# ============================================================

cat > "$BACKEND/wallet/LedgerVerifier.php" <<'PHP'
<?php
declare(strict_types=1);

/**
 * LedgerVerifier – Full chain validation utility (recommended for periodic audits).
 */
final class LedgerVerifier
{
    public static function verifyChain(int $userId): array
    {
        $db = Database::conn();
        $stmt = $db->prepare(
            "SELECT id, sequence_id, direction, amount, ref_type, ref_id, provider,
                    fx_rate, base_amount, prev_hash, hash, balance_after, created_at
               FROM wallet_ledger
              WHERE user_id = ?
              ORDER BY sequence_id ASC"
        );
        $stmt->execute([$userId]);
        $entries = $stmt->fetchAll(PDO::FETCH_ASSOC);

        if (empty($entries)) {
            return ['valid' => true, 'reason' => 'no_entries'];
        }

        $prevHash = '0';
        $runningBalance = '0';

        foreach ($entries as $i => $entry) {
            // Recompute hash
            $payload = $userId . '|' . $entry['sequence_id'] . '|' . $entry['direction'] . '|' .
                       $entry['amount'] . '|' . $entry['ref_type'] . '|' . $entry['ref_id'] . '|' .
                       ($entry['provider'] ?? '') . '|' . ($entry['fx_rate'] ?? '') . '|' .
                       ($entry['base_amount'] ?? '') . '|' . $prevHash;

            $secret = defined('WALLET_HMAC_SECRET') ? WALLET_HMAC_SECRET : '';
            $computed = $secret
                ? hash_hmac('sha256', $payload, $secret)
                : hash('sha256', $payload);

            if ($computed !== $entry['hash']) {
                return ['valid' => false, 'failed_at' => $i, 'reason' => 'hash_mismatch'];
            }

            // Balance continuity check
            $expectedBalance = ($entry['direction'] === 'credit')
                ? bcadd($runningBalance, $entry['amount'], 6)
                : bcsub($runningBalance, $entry['amount'], 6);

            if (bccomp($expectedBalance, $entry['balance_after'], 6) !== 0) {
                return ['valid' => false, 'failed_at' => $i, 'reason' => 'balance_inconsistency'];
            }

            $prevHash = $entry['hash'];
            $runningBalance = $entry['balance_after'];
        }

        return ['valid' => true, 'entries_verified' => count($entries)];
    }

    // Optional: reconcile cache vs ledger (run via compliance dashboard)
    public static function reconcileCache(int $userId): bool
    {
        $ledgerBalance = '0';
        $stmt = Database::conn()->prepare(
            "SELECT COALESCE(SUM(CASE WHEN direction='credit' THEN amount ELSE -amount END), '0')
               FROM wallet_ledger WHERE user_id = ?"
        );
        $stmt->execute([$userId]);
        $ledgerBalance = (string)$stmt->fetchColumn();

        $cacheStmt = Database::conn()->prepare(
            "SELECT balance FROM wallets WHERE user_id = ?"
        );
        $cacheStmt->execute([$userId]);
        $cacheBalance = (string)$cacheStmt->fetchColumn();

        return bccomp($ledgerBalance, $cacheBalance, 6) === 0;
    }
}
PHP

echo "[PHASE 30] ✓ Wallet ledger regenerated with enhanced security & verification."
