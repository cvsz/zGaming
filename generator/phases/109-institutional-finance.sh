#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 109] INSTITUTIONAL FINANCE HARDENING"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"
SCRIPTS_DIR="$ROOT/scripts"

mkdir -p "$BACKEND/db" "$BACKEND/finance" "$BACKEND/signer" "$BACKEND/lib" "$SCRIPTS_DIR"

cat > "$BACKEND/db/institutional_finance.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS wallets (
  user_id BIGINT PRIMARY KEY,
  balance DECIMAL(18,6) NOT NULL DEFAULT 0,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

SET @wallet_type_col := (
  SELECT COUNT(*)
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wallets' AND column_name = 'wallet_type'
);
SET @wallet_type_sql := IF(@wallet_type_col = 0,
  "ALTER TABLE wallets ADD COLUMN wallet_type ENUM('hot','cold') NOT NULL DEFAULT 'hot' AFTER balance",
  'SELECT 1');
PREPARE stmt_wallet_type FROM @wallet_type_sql;
EXECUTE stmt_wallet_type;
DEALLOCATE PREPARE stmt_wallet_type;

SET @wallet_region_col := (
  SELECT COUNT(*)
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wallets' AND column_name = 'region'
);
SET @wallet_region_sql := IF(@wallet_region_col = 0,
  "ALTER TABLE wallets ADD COLUMN region VARCHAR(32) NOT NULL DEFAULT 'us-east-1' AFTER wallet_type",
  'SELECT 1');
PREPARE stmt_wallet_region FROM @wallet_region_sql;
EXECUTE stmt_wallet_region;
DEALLOCATE PREPARE stmt_wallet_region;

CREATE TABLE IF NOT EXISTS withdrawal_queue (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  amount DECIMAL(18,6) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'USD',
  status ENUM('pending','approved','rejected','processing','done','failed') NOT NULL DEFAULT 'pending',
  needs_cold_approval TINYINT(1) NOT NULL DEFAULT 0,
  approved_by VARCHAR(64) DEFAULT NULL,
  approved_at TIMESTAMP NULL DEFAULT NULL,
  idempotency_key VARCHAR(128) NOT NULL,
  region VARCHAR(32) NOT NULL DEFAULT 'us-east-1',
  failure_reason VARCHAR(255) DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_withdrawal_idempotency (idempotency_key),
  KEY idx_withdrawal_status (status, created_at)
);

CREATE TABLE IF NOT EXISTS cold_wallet_topups (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  hot_wallet_user_id BIGINT NOT NULL,
  cold_wallet_user_id BIGINT NOT NULL,
  amount DECIMAL(18,6) NOT NULL,
  status ENUM('pending','approved','done','failed') NOT NULL DEFAULT 'pending',
  approved_by VARCHAR(64) DEFAULT NULL,
  approved_at TIMESTAMP NULL DEFAULT NULL,
  region VARCHAR(32) NOT NULL DEFAULT 'us-east-1',
  idempotency_key VARCHAR(128) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_topup_idempotency (idempotency_key)
);

CREATE TABLE IF NOT EXISTS settlement_queue (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  type ENUM('bet','payout','deposit','withdrawal') NOT NULL,
  payload JSON NOT NULL,
  status ENUM('pending','processing','done','failed') NOT NULL DEFAULT 'pending',
  retries INT NOT NULL DEFAULT 0,
  idempotency_key VARCHAR(128) NOT NULL,
  region VARCHAR(32) NOT NULL DEFAULT 'us-east-1',
  locked_by_region VARCHAR(32) DEFAULT NULL,
  locked_at TIMESTAMP NULL DEFAULT NULL,
  last_error VARCHAR(255) DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_settlement_idempotency (idempotency_key),
  KEY idx_settlement_status (status, retries, created_at)
);

CREATE TABLE IF NOT EXISTS psp_transactions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  provider VARCHAR(64) NOT NULL,
  external_id VARCHAR(128) NOT NULL,
  amount DECIMAL(18,6) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'USD',
  tx_timestamp TIMESTAMP NOT NULL,
  region VARCHAR(32) NOT NULL DEFAULT 'us-east-1',
  raw_payload JSON,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_psp_external (provider, external_id)
);

CREATE TABLE IF NOT EXISTS internal_transactions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  tx_type ENUM('bet','payout','deposit','withdrawal','transfer') NOT NULL,
  external_id VARCHAR(128) DEFAULT NULL,
  user_id BIGINT DEFAULT NULL,
  amount DECIMAL(18,6) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'USD',
  tx_timestamp TIMESTAMP NOT NULL,
  region VARCHAR(32) NOT NULL DEFAULT 'us-east-1',
  metadata JSON,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_internal_external (tx_type, external_id)
);

CREATE TABLE IF NOT EXISTS reconciliation_report (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  report_date DATE NOT NULL,
  mismatch_type ENUM('missing_internal','missing_psp','amount_mismatch','duplicate') NOT NULL,
  external_id VARCHAR(128) DEFAULT NULL,
  provider VARCHAR(64) DEFAULT NULL,
  details JSON NOT NULL,
  status ENUM('open','acknowledged','resolved') NOT NULL DEFAULT 'open',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_recon_report_date (report_date, mismatch_type)
);

CREATE TABLE IF NOT EXISTS aml_flags (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  rule_code VARCHAR(64) NOT NULL,
  severity ENUM('low','medium','high','critical') NOT NULL DEFAULT 'medium',
  details JSON NOT NULL,
  related_tx_id BIGINT DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_aml_user_created (user_id, created_at)
);

CREATE TABLE IF NOT EXISTS aml_reports (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  report_type ENUM('STR') NOT NULL,
  report_ref VARCHAR(128) NOT NULL,
  payload JSON NOT NULL,
  exported_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_aml_report_ref (report_ref)
);

CREATE TABLE IF NOT EXISTS aml_audit_log (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  event_type VARCHAR(64) NOT NULL,
  payload JSON NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$
DROP TRIGGER IF EXISTS aml_audit_log_immutable_update$$
CREATE TRIGGER aml_audit_log_immutable_update
BEFORE UPDATE ON aml_audit_log
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'aml_audit_log is immutable';
END$$
DROP TRIGGER IF EXISTS aml_audit_log_immutable_delete$$
CREATE TRIGGER aml_audit_log_immutable_delete
BEFORE DELETE ON aml_audit_log
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'aml_audit_log is immutable';
END$$
DELIMITER ;

CREATE TABLE IF NOT EXISTS fraud_events (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  event_type VARCHAR(64) NOT NULL,
  risk_score INT NOT NULL,
  blocked TINYINT(1) NOT NULL DEFAULT 0,
  region VARCHAR(32) NOT NULL DEFAULT 'us-east-1',
  details JSON NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_fraud_user_created (user_id, created_at)
);
SQL

cat > "$BACKEND/lib/Database.php" <<'PHP'
<?php

declare(strict_types=1);

final class Database
{
    private static ?PDO $pdo = null;

    public static function conn(): PDO
    {
        if (self::$pdo instanceof PDO) {
            return self::$pdo;
        }

        $dsn = getenv('DB_DSN');
        if ($dsn === false || $dsn === '') {
            $host = getenv('DB_HOST') ?: '127.0.0.1';
            $name = getenv('DB_NAME') ?: 'casino';
            $port = getenv('DB_PORT') ?: '3306';
            $dsn = "mysql:host={$host};port={$port};dbname={$name};charset=utf8mb4";
        }

        $user = getenv('DB_USER') ?: 'casino';
        $pass = getenv('DB_PASSWORD') ?: (getenv('DB_PASS') ?: 'casino');
        self::$pdo = new PDO($dsn, $user, $pass, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);

        return self::$pdo;
    }
}
PHP

cat > "$BACKEND/signer/WalletSigner.php" <<'PHP'
<?php

declare(strict_types=1);

interface WalletSigner
{
    public function signTransaction(string $unsignedPayload): string;

    public function getAddress(): string;
}
PHP

cat > "$BACKEND/signer/LocalSigner.php" <<'PHP'
<?php

declare(strict_types=1);

final class LocalSigner implements WalletSigner
{
    public function __construct(private readonly string $privateKey, private readonly string $address)
    {
    }

    public function signTransaction(string $unsignedPayload): string
    {
        return hash_hmac('sha256', $unsignedPayload, $this->privateKey);
    }

    public function getAddress(): string
    {
        return $this->address;
    }
}
PHP

cat > "$BACKEND/signer/HsmSigner.php" <<'PHP'
<?php

declare(strict_types=1);

final class HsmSigner implements WalletSigner
{
    public function __construct(private readonly string $keyHandle, private readonly string $address)
    {
    }

    public function signTransaction(string $unsignedPayload): string
    {
        return sprintf('hsm_stub:%s:%s', $this->keyHandle, hash('sha256', $unsignedPayload));
    }

    public function getAddress(): string
    {
        return $this->address;
    }
}
PHP

cat > "$BACKEND/finance/WalletTierService.php" <<'PHP'
<?php

declare(strict_types=1);

final class WalletTierService
{
    public function __construct(private readonly PDO $db)
    {
    }

    public function creditDeposit(int $userId, string $amount, string $idempotencyKey, string $region = 'us-east-1'): void
    {
        $stmt = $this->db->prepare('INSERT INTO internal_transactions (tx_type, external_id, user_id, amount, tx_timestamp, region) VALUES (\'deposit\', ?, ?, ?, UTC_TIMESTAMP(), ?) ON DUPLICATE KEY UPDATE external_id=external_id');
        $stmt->execute([$idempotencyKey, $userId, $amount, $region]);
        $this->db->prepare('UPDATE wallets SET balance = balance + ?, wallet_type = \'hot\', region = ? WHERE user_id = ?')->execute([$amount, $region, $userId]);
    }

    public function requestWithdrawal(int $userId, string $amount, string $idempotencyKey, string $region = 'us-east-1'): int
    {
        $this->db->beginTransaction();
        $this->db->prepare('SELECT user_id FROM wallets WHERE user_id = ? FOR UPDATE')->execute([$userId]);
        $hotBalance = (string)($this->db->query("SELECT balance FROM wallets WHERE user_id = {$userId} AND wallet_type='hot' LIMIT 1")->fetchColumn() ?: '0');
        $needsColdApproval = bccomp($hotBalance, $amount, 6) < 0 ? 1 : 0;

        $stmt = $this->db->prepare('INSERT INTO withdrawal_queue (user_id, amount, needs_cold_approval, idempotency_key, region) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE id=id');
        $stmt->execute([$userId, $amount, $needsColdApproval, $idempotencyKey, $region]);
        $id = (int)$this->db->lastInsertId();

        if ($needsColdApproval === 0) {
            $this->db->prepare('UPDATE wallets SET balance = balance - ? WHERE user_id = ? AND wallet_type = \'hot\'')->execute([$amount, $userId]);
            $this->db->prepare('UPDATE withdrawal_queue SET status = \'approved\' WHERE id = ?')->execute([$id]);
        }

        $this->db->commit();
        return $id;
    }

    public function approveColdWithdrawal(int $queueId, string $approver): void
    {
        $this->db->prepare('UPDATE withdrawal_queue SET status=\'approved\', approved_by=?, approved_at=UTC_TIMESTAMP() WHERE id=? AND needs_cold_approval=1 AND status=\'pending\'')->execute([$approver, $queueId]);
    }

    public function topUpHotFromCold(int $hotWalletUserId, int $coldWalletUserId, string $amount, string $idempotencyKey, string $approver, string $region = 'us-east-1'): void
    {
        $this->db->beginTransaction();
        $this->db->prepare('INSERT INTO cold_wallet_topups (hot_wallet_user_id, cold_wallet_user_id, amount, status, approved_by, approved_at, idempotency_key, region) VALUES (?, ?, ?, \'approved\', ?, UTC_TIMESTAMP(), ?, ?) ON DUPLICATE KEY UPDATE id=id')->execute([$hotWalletUserId, $coldWalletUserId, $amount, $approver, $idempotencyKey, $region]);
        $this->db->prepare('UPDATE wallets SET balance = balance - ? WHERE user_id = ? AND wallet_type = \'cold\'')->execute([$amount, $coldWalletUserId]);
        $this->db->prepare('UPDATE wallets SET balance = balance + ? WHERE user_id = ? AND wallet_type = \'hot\'')->execute([$amount, $hotWalletUserId]);
        $this->db->commit();
    }
}
PHP

cat > "$BACKEND/finance/SettlementWorker.php" <<'PHP'
<?php

declare(strict_types=1);

final class SettlementWorker
{
    public function __construct(private readonly PDO $db, private readonly string $region)
    {
    }

    public function runOnce(): bool
    {
        $this->db->beginTransaction();
        $stmt = $this->db->prepare("SELECT id, type, payload, retries, idempotency_key FROM settlement_queue WHERE status='pending' AND retries < 5 ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED");
        $stmt->execute();
        $job = $stmt->fetch();

        if (!$job) {
            $this->db->commit();
            return false;
        }

        $this->db->prepare("UPDATE settlement_queue SET status='processing', locked_by_region=?, locked_at=UTC_TIMESTAMP() WHERE id=?")->execute([$this->region, $job['id']]);
        $this->db->commit();

        try {
            $this->processJob($job);
            $this->db->prepare("UPDATE settlement_queue SET status='done' WHERE id=? AND idempotency_key=?")->execute([$job['id'], $job['idempotency_key']]);
        } catch (Throwable $e) {
            $this->db->prepare("UPDATE settlement_queue SET status='pending', retries=retries+1, last_error=? WHERE id=?")->execute([substr($e->getMessage(), 0, 250), $job['id']]);
        }

        return true;
    }

    private function processJob(array $job): void
    {
        $payload = json_decode((string)$job['payload'], true, 512, JSON_THROW_ON_ERROR);
        $this->db->prepare('INSERT INTO internal_transactions (tx_type, external_id, user_id, amount, tx_timestamp, region, metadata) VALUES (?, ?, ?, ?, UTC_TIMESTAMP(), ?, ?) ON DUPLICATE KEY UPDATE external_id=external_id')
            ->execute([$job['type'], $job['idempotency_key'], $payload['user_id'] ?? null, $payload['amount'] ?? '0', $this->region, json_encode($payload, JSON_THROW_ON_ERROR)]);
    }
}
PHP

cat > "$BACKEND/finance/ReconciliationEngine.php" <<'PHP'
<?php

declare(strict_types=1);

final class ReconciliationEngine
{
    public function __construct(private readonly PDO $db)
    {
    }

    public function runForDate(string $date): void
    {
        $this->db->prepare("INSERT INTO reconciliation_report (report_date, mismatch_type, external_id, provider, details)
            SELECT ?, 'missing_internal', p.external_id, p.provider,
              JSON_OBJECT('psp_amount', p.amount, 'tx_timestamp', p.tx_timestamp)
            FROM psp_transactions p
            LEFT JOIN internal_transactions i ON i.external_id = p.external_id
            WHERE DATE(p.tx_timestamp)=? AND i.id IS NULL")
            ->execute([$date, $date]);

        $this->db->prepare("INSERT INTO reconciliation_report (report_date, mismatch_type, external_id, provider, details)
            SELECT ?, 'amount_mismatch', p.external_id, p.provider,
              JSON_OBJECT('psp_amount', p.amount, 'internal_amount', i.amount)
            FROM psp_transactions p
            JOIN internal_transactions i ON i.external_id = p.external_id
            WHERE DATE(p.tx_timestamp)=? AND i.amount <> p.amount")
            ->execute([$date, $date]);

        $this->db->prepare("INSERT INTO reconciliation_report (report_date, mismatch_type, external_id, provider, details)
            SELECT ?, 'duplicate', external_id, provider,
              JSON_OBJECT('duplicate_count', COUNT(*))
            FROM psp_transactions
            WHERE DATE(tx_timestamp)=?
            GROUP BY external_id, provider
            HAVING COUNT(*) > 1")
            ->execute([$date, $date]);
    }
}
PHP

cat > "$BACKEND/finance/AmlEngine.php" <<'PHP'
<?php

declare(strict_types=1);

final class AmlEngine
{
    public function __construct(private readonly PDO $db)
    {
    }

    public function scanUser(int $userId): void
    {
        $this->flagLargeTransactions($userId);
        $this->flagRapidTransactions($userId);
    }

    private function flagLargeTransactions(int $userId): void
    {
        $stmt = $this->db->prepare("SELECT id, amount FROM internal_transactions WHERE user_id=? AND amount > 10000 ORDER BY id DESC LIMIT 20");
        $stmt->execute([$userId]);
        foreach ($stmt->fetchAll() as $row) {
            $this->createFlag($userId, 'large_transaction', 'high', ['amount' => $row['amount']], (int)$row['id']);
        }
    }

    private function flagRapidTransactions(int $userId): void
    {
        $stmt = $this->db->prepare("SELECT COUNT(*) FROM internal_transactions WHERE user_id=? AND tx_timestamp >= (UTC_TIMESTAMP() - INTERVAL 1 MINUTE)");
        $stmt->execute([$userId]);
        $count = (int)$stmt->fetchColumn();
        if ($count > 5) {
            $this->createFlag($userId, 'velocity_1m', 'critical', ['count_1m' => $count], null);
        }
    }

    private function createFlag(int $userId, string $rule, string $severity, array $details, ?int $txId): void
    {
        $reportRef = sprintf('STR-%s-%d-%s', gmdate('YmdHis'), $userId, bin2hex(random_bytes(4)));
        $payloadJson = json_encode($details, JSON_THROW_ON_ERROR);

        $this->db->prepare('INSERT INTO aml_flags (user_id, rule_code, severity, details, related_tx_id) VALUES (?, ?, ?, ?, ?)')
            ->execute([$userId, $rule, $severity, $payloadJson, $txId]);
        $this->db->prepare("INSERT INTO aml_reports (report_type, report_ref, payload) VALUES ('STR', ?, JSON_OBJECT('user_id', ?, 'rule', ?, 'severity', ?, 'details', CAST(? AS JSON)))")
            ->execute([$reportRef, $userId, $rule, $severity, $payloadJson]);
        $this->db->prepare("INSERT INTO aml_audit_log (event_type, payload) VALUES ('str_generated', JSON_OBJECT('report_ref', ?, 'user_id', ?, 'rule', ?))")
            ->execute([$reportRef, $userId, $rule]);
    }
}
PHP

cat > "$BACKEND/finance/FraudEngine.php" <<'PHP'
<?php

declare(strict_types=1);

final class FraudEngine
{
    public function __construct(private readonly PDO $db, private readonly string $region = 'us-east-1')
    {
    }

    public function assess(int $userId, float $betAmount, ?string $country): bool
    {
        $score = 0;
        $blocked = false;

        $rapidStmt = $this->db->prepare("SELECT COUNT(*) FROM internal_transactions WHERE user_id=? AND tx_type='bet' AND tx_timestamp >= (UTC_TIMESTAMP() - INTERVAL 30 SECOND)");
        $rapidStmt->execute([$userId]);
        $rapidCount = (int)$rapidStmt->fetchColumn();
        if ($rapidCount > 20) {
            $score += 70;
        }

        $avgStmt = $this->db->prepare("SELECT COALESCE(AVG(amount),0) FROM internal_transactions WHERE user_id=? AND tx_type='bet' AND tx_timestamp >= (UTC_TIMESTAMP() - INTERVAL 1 DAY)");
        $avgStmt->execute([$userId]);
        $avg = (float)$avgStmt->fetchColumn();
        if ($avg > 0 && $betAmount > ($avg * 8)) {
            $score += 40;
        }

        if ($country !== null && $country !== '') {
            $geoStmt = $this->db->prepare("SELECT JSON_EXTRACT(metadata, '$.country') AS country FROM internal_transactions WHERE user_id=? AND tx_type='bet' ORDER BY id DESC LIMIT 1");
            $geoStmt->execute([$userId]);
            $lastCountry = (string)$geoStmt->fetchColumn();
            if ($lastCountry !== '' && $lastCountry !== 'null' && trim($lastCountry, '"') !== $country) {
                $score += 30;
            }
        }

        if ($score >= 80) {
            $blocked = true;
        }

        $this->db->prepare('INSERT INTO fraud_events (user_id, event_type, risk_score, blocked, region, details) VALUES (?, ?, ?, ?, ?, ?)')
            ->execute([$userId, 'bet_assessment', $score, $blocked ? 1 : 0, $this->region, json_encode(['bet_amount' => $betAmount, 'country' => $country, 'rapid_count' => $rapidCount], JSON_THROW_ON_ERROR)]);

        return $blocked;
    }
}
PHP

cat > "$SCRIPTS_DIR/finance-settlement-worker.php" <<'PHP'
<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';
require_once __DIR__ . '/../backend/finance/SettlementWorker.php';

$region = getenv('WORKER_REGION') ?: 'us-east-1';
$loops = (int)(getenv('WORKER_LOOPS') ?: '100');
$sleepMicros = (int)(getenv('WORKER_IDLE_SLEEP_US') ?: '250000');

$worker = new SettlementWorker(Database::conn(), $region);
for ($i = 0; $i < $loops; $i++) {
    $processed = $worker->runOnce();
    if (!$processed) {
        usleep($sleepMicros);
    }
}

echo "settlement worker complete\n";
PHP

cat > "$SCRIPTS_DIR/reconcile-daily.php" <<'PHP'
<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';
require_once __DIR__ . '/../backend/finance/ReconciliationEngine.php';

$date = $argv[1] ?? gmdate('Y-m-d', time() - 86400);
$engine = new ReconciliationEngine(Database::conn());
$engine->runForDate($date);

echo "reconciliation complete for {$date}\n";
PHP

echo "✅ Institutional finance components ready"
