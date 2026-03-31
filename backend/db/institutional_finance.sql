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
