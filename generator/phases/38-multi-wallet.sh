#!/usr/bin/env bash
# =============================================================================
# generator/phases/38-multi-wallet.sh – Regenerated Multi-Wallet per Provider (Deep Impact Drive v2.2)
# =============================================================================
# Based exactly on the source you provided.
# Improvements: immutable hash-chained ledger (Phase 30 style), BC Math,
#               FxService integration (Phase 36), full ACID + verification.
# =============================================================================

ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 38] MULTI-WALLET PER PROVIDER (Regenerated v2.2)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"

# Ensure required directories exist
mkdir -p \
  "$BACKEND"/{wallet,db,core} \
  "$BACKEND/api/admin"

# ============================================================
# 1. Wallet per Provider Schema (hardened + immutable)
# ============================================================

cat > "$BACKEND/db/multi_wallet.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS wallets (
  user_id BIGINT NOT NULL,
  provider VARCHAR(32) NOT NULL,
  currency CHAR(3) NOT NULL,
  balance DECIMAL(18,6) NOT NULL DEFAULT 0 COMMENT 'Cache only – ledger is authoritative',
  PRIMARY KEY (user_id, provider, currency)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS wallet_ledger_multi (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  provider VARCHAR(32) NOT NULL,
  sequence_id BIGINT NOT NULL,
  direction ENUM('debit','credit') NOT NULL,
  amount DECIMAL(18,6) NOT NULL,
  currency CHAR(3) NOT NULL,
  fx_rate_id BIGINT NOT NULL,
  fx_rate DECIMAL(18,8) NOT NULL,
  base_amount DECIMAL(18,6) NOT NULL,
  ref VARCHAR(128) NOT NULL,
  prev_hash CHAR(64) NOT NULL,
  hash CHAR(64) NOT NULL,
  balance_after DECIMAL(18,6) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_user_provider_sequence (user_id, provider, sequence_id),
  UNIQUE KEY uniq_ref (user_id, provider, ref),
  KEY idx_provider_created (provider, created_at)
) ENGINE=InnoDB;

-- Immutability triggers (same as Phase 30)
DELIMITER $$
DROP TRIGGER IF EXISTS wallet_ledger_multi_immutable_update$$
CREATE TRIGGER wallet_ledger_multi_immutable_update
BEFORE UPDATE ON wallet_ledger_multi FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'wallet_ledger_multi is immutable';
END$$

DROP TRIGGER IF EXISTS wallet_ledger_multi_immutable_delete$$
CREATE TRIGGER wallet_ledger_multi_immutable_delete
BEFORE DELETE ON wallet_ledger_multi FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'wallet_ledger_multi is immutable';
END$$
DELIMITER ;
SQL

# ============================================================
# 2. Provider-Agnostic Wallet Domain Service (BC Math + hash chain)
# ============================================================

cat > "$BACKEND/wallet/ProviderWallet.php" <<'PHP'
<?php
declare(strict_types=1);

use PDO;
use PDOException;
use Throwable;

/**
 * Hardened Multi-Wallet per Provider – v2.2 (aligned with Phase 30 ledger).
 */
final class ProviderWallet
{
    private const SCALE = 6;
    private const MAX_RETRIES = 3;

    private static function conn(): PDO { return Database::conn(); }

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

    public static function credit(
        int $userId,
        string $provider,
        string $amount,
        string $currency,
        string $ref,
        string $baseCurrency = 'USD'
    ): array {
        if (bccomp($amount, '0', self::SCALE) <= 0) {
            throw new InvalidArgumentException('invalid_amount_non_positive');
        }

        $fxSnapshot = FxService::getRateSnapshot($currency, $baseCurrency);
        $fxRate = $fxSnapshot['rate'];
        $fxRateId = $fxSnapshot['rate_id'];
        $baseAmount = bcmul($amount, $fxRate, self::SCALE);

        $db = self::conn();
        for ($attempt = 1; $attempt <= self::MAX_RETRIES; ++$attempt) {
            $db->exec("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE");
            $db->beginTransaction();

            try {
                // Idempotency check
                $idemStmt = $db->prepare(
                    "SELECT 1 FROM wallet_ledger_multi
                     WHERE user_id = ? AND provider = ? AND ref = ? LIMIT 1 FOR UPDATE"
                );
                $idemStmt->execute([$userId, $provider, $ref]);
                if ($idemStmt->fetchColumn()) {
                    $db->commit();
                    return self::getBalance($userId, $provider, $currency);
                }

                // Lock provider wallet projection row
                $walletStmt = $db->prepare(
                    "SELECT balance FROM wallets
                     WHERE user_id = ? AND provider = ? AND currency = ?
                     FOR UPDATE"
                );
                $walletStmt->execute([$userId, $provider, $currency]);

                // Lock base wallet projection row
                $baseWalletStmt = $db->prepare(
                    "SELECT balance FROM wallets
                     WHERE user_id = ? AND provider = '__BASE__' AND currency = ?
                     FOR UPDATE"
                );
                $baseWalletStmt->execute([$userId, $baseCurrency]);

                // Previous ledger row for chaining (scoped to user+provider)
                $prevStmt = $db->prepare(
                    "SELECT hash, balance_after, sequence_id
                       FROM wallet_ledger_multi
                      WHERE user_id = ? AND provider = ?
                      ORDER BY sequence_id DESC LIMIT 1 FOR UPDATE"
                );
                $prevStmt->execute([$userId, $provider]);
                $prev = $prevStmt->fetch(PDO::FETCH_ASSOC) ?: [
                    'hash' => str_repeat('0', 64),
                    'balance_after' => '0',
                    'sequence_id' => 0
                ];

                $sequenceId = (int)$prev['sequence_id'] + 1;
                $balanceAfter = self::decimalAdd($prev['balance_after'], $amount);

                // HMAC-ready hash
                $payload = implode('|', [
                    $userId, $provider, $sequenceId, $amount, $currency,
                    $fxRate, $baseAmount, $ref, $prev['hash']
                ]);
                $secret = defined('WALLET_HMAC_SECRET') ? WALLET_HMAC_SECRET : '';
                $hash = $secret
                    ? hash_hmac('sha256', $payload, $secret)
                    : hash('sha256', $payload);

                // Insert immutable ledger entry
                $db->prepare(
                    "INSERT INTO wallet_ledger_multi
                     (user_id, provider, sequence_id, direction, amount, currency,
                      fx_rate_id, fx_rate, base_amount, ref, prev_hash, hash, balance_after)
                     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)"
                )->execute([
                    $userId, $provider, $sequenceId, 'credit', $amount, $currency,
                    $fxRateId, $fxRate, $baseAmount, $ref, $prev['hash'], $hash, $balanceAfter
                ]);

                // Update provider wallet cache
                $db->prepare(
                    "INSERT INTO wallets (user_id, provider, currency, balance)
                     VALUES (?,?,?,?)
                     ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)"
                )->execute([$userId, $provider, $currency, $amount]);

                // Update __BASE__ accounting wallet
                $db->prepare(
                    "INSERT INTO wallets (user_id, provider, currency, balance)
                     VALUES (?,?,?,?)
                     ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)"
                )->execute([$userId, '__BASE__', $baseCurrency, $baseAmount]);

                $db->commit();

                return self::getBalance($userId, $provider, $currency);

            } catch (PDOException $e) {
                if ($db->inTransaction()) $db->rollBack();
                if ($attempt < self::MAX_RETRIES && in_array($e->errorInfo[1] ?? 0, [1213, 1205], true)) {
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

    private static function getBalance(int $userId, string $provider, string $currency): array
    {
        $stmt = self::conn()->prepare(
            "SELECT balance FROM wallets
             WHERE user_id = ? AND provider = ? AND currency = ?"
        );
        $stmt->execute([$userId, $provider, $currency]);
        return [
            'provider' => $provider,
            'currency' => $currency,
            'balance' => (string)$stmt->fetchColumn()
        ];
    }

    public static function getAll(int $userId): array
    {
        $stmt = self::conn()->prepare(
            "SELECT provider, currency, balance FROM wallets WHERE user_id = ?"
        );
        $stmt->execute([$userId]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
}
PHP

# ============================================================
# 3. Provider Wallet Adapter (for callbacks – uses FxService)
# ============================================================

cat > "$BACKEND/wallet/ProviderWalletAdapter.php" <<'PHP'
<?php
declare(strict_types=1);

/**
 * Adapter for provider callbacks – now uses hardened FxService (Phase 36).
 */
final class ProviderWalletAdapter
{
    public static function credit(
        int $userId,
        string $provider,
        string $amount,
        string $currency,
        string $ref
    ): array {
        $base = getenv('BASE_CURRENCY') ?: 'USD';
        return ProviderWallet::credit($userId, $provider, $amount, $currency, $ref, $base);
    }
}
PHP

# ============================================================
# 4. Multi-Ledger Verifier (mirrors Phase 30 LedgerVerifier)
# ============================================================

cat > "$BACKEND/wallet/MultiLedgerVerifier.php" <<'PHP'
<?php
declare(strict_types=1);

/**
 * Verifier for multi-wallet ledger chain (per user + provider).
 */
final class MultiLedgerVerifier
{
    public static function verifyChain(int $userId, string $provider): array
    {
        $db = Database::conn();
        $stmt = $db->prepare(
            "SELECT sequence_id, direction, amount, currency, fx_rate, base_amount, ref,
                    provider,
                    prev_hash, hash, balance_after
               FROM wallet_ledger_multi
              WHERE user_id = ? AND provider = ?
              ORDER BY sequence_id ASC"
        );
        $stmt->execute([$userId, $provider]);
        $entries = $stmt->fetchAll(PDO::FETCH_ASSOC);

        if (empty($entries)) {
            return ['valid' => true, 'reason' => 'no_entries'];
        }

        $prevHash = str_repeat('0', 64);
        $runningBalance = '0';

        foreach ($entries as $i => $e) {
            $payload = implode('|', [
                $userId, $e['provider'], $e['sequence_id'], $e['amount'],
                $e['currency'], $e['fx_rate'], $e['base_amount'], $e['ref'], $prevHash
            ]);
            $secret = defined('WALLET_HMAC_SECRET') ? WALLET_HMAC_SECRET : '';
            $computed = $secret
                ? hash_hmac('sha256', $payload, $secret)
                : hash('sha256', $payload);

            if ($computed !== $e['hash']) {
                return ['valid' => false, 'failed_at' => $i, 'reason' => 'hash_mismatch'];
            }

            $expected = bcadd($runningBalance, $e['amount'], 6); // credit only in this phase
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
# 5. Admin API – View Multi-Wallet Balances (unchanged layout)
# ============================================================

cat > "$BACKEND/api/admin/wallets.php" <<'PHP'
<?php
require_once __DIR__ . '/../../core/Bootstrap.php';
Auth::requireRole('admin');
$userId = (int)($_GET['user'] ?? 0);
echo json_encode(ProviderWallet::getAll($userId));
PHP

# ============================================================
# 6. Documentation (enhanced)
# ============================================================

cat > "$BACKEND/wallet/MULTI_WALLET.md" <<'MD'
# Multi-Wallet per Provider (v2.2 – Hardened)

## Model
- wallets: composite PK `(user_id, provider, currency)` – cache only
- wallet_ledger_multi: immutable, hash-chained per `(user_id, provider)`

## Guarantees (aligned with Phase 30)
- Full ACID + SERIALIZABLE + deadlock retry
- Idempotent via `(user_id, provider, ref)`
- BC Math precision (18,6)
- FX snapshot via FxService::getRateSnapshot() with pinned `fx_rate_id`
- Tamper-evident hash chaining + immutable triggers
- Provider wallet + __BASE__ wallet updates are committed in one transaction
- Negative balances allowed by design (business-rule enforcement is external)

## Verification
MultiLedgerVerifier::verifyChain($userId, $provider)

## Accounting
- Provider wallet → gameplay balances
- __BASE__ wallet → finance / P&L

## Integration
ProviderWalletAdapter::credit() for callbacks (replay-safe)
MD

echo "✅ PHASE 38 COMPLETE – Multi-wallet per provider hardened & ready"
