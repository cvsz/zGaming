<?php

declare(strict_types=1);

require_once __DIR__ . '/../compliance/KycService.php';
require_once __DIR__ . '/../audit/AuditTrail.php';
require_once __DIR__ . '/../observability/StructuredLogger.php';

final class WalletTierService
{
    private readonly StructuredLogger $logger;

    public function __construct(
        private readonly PDO $db,
        private readonly ?KycService $kycService = null,
        private readonly ?AuditTrail $auditTrail = null
    ) {
        $this->logger = new StructuredLogger('wallet-tier-service');
    }

    public function creditDeposit(int $userId, string $amount, string $idempotencyKey, string $region = 'us-east-1', ?string $transactionId = null): void
    {
        $transactionId ??= self::newTransactionId();
        $stmt = $this->db->prepare('INSERT INTO internal_transactions (transaction_id, tx_type, external_id, user_id, amount, tx_timestamp, region) VALUES (?, \'deposit\', ?, ?, ?, UTC_TIMESTAMP(), ?) ON DUPLICATE KEY UPDATE external_id=external_id');
        $stmt->execute([$transactionId, $idempotencyKey, $userId, $amount, $region]);
        $this->db->prepare('UPDATE wallets SET balance = balance + ?, wallet_type = \'hot\', region = ? WHERE user_id = ?')->execute([$amount, $region, $userId]);
        $this->auditTrail?->append('system', 'settlement', 'deposit_credited', 'wallet', (string)$userId, ['amount' => $amount, 'transaction_id' => $transactionId]);
    }

    public function requestWithdrawal(int $userId, string $amount, string $idempotencyKey, string $region = 'us-east-1', ?string $transactionId = null): int
    {

        if ($this->isReadOnlyMode()) {
            throw new RuntimeException('SERVICE_READ_ONLY_MODE');
        }

        if ($this->isWithdrawalsDisabled()) {
            throw new RuntimeException('WITHDRAWALS_DISABLED');
        }

        if ($this->isUserFrozen($userId)) {
            throw new RuntimeException('USER_WALLET_FROZEN');
        }

        if ((bool)(getenv('REQUIRE_KYC_FOR_WITHDRAWALS') ?: false) && $this->kycService !== null && !$this->kycService->isWithdrawalAllowed($userId)) {
            throw new RuntimeException('WITHDRAWAL_REQUIRES_VERIFIED_KYC');
        }

        $transactionId ??= self::newTransactionId();
        $this->db->beginTransaction();
        $this->db->prepare('SELECT user_id FROM wallets WHERE user_id = ? FOR UPDATE')->execute([$userId]);
        $hotBalance = (string)($this->db->query("SELECT balance FROM wallets WHERE user_id = {$userId} AND wallet_type='hot' LIMIT 1")->fetchColumn() ?: '0');
        $needsColdApproval = bccomp($hotBalance, $amount, 6) < 0 ? 1 : 0;

        $stmt = $this->db->prepare('INSERT INTO withdrawal_queue (transaction_id, user_id, amount, needs_cold_approval, idempotency_key, region) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE id=id');
        $stmt->execute([$transactionId, $userId, $amount, $needsColdApproval, $idempotencyKey, $region]);
        $id = (int)$this->db->lastInsertId();

        if ($needsColdApproval === 0) {
            $this->db->prepare('UPDATE wallets SET balance = balance - ? WHERE user_id = ? AND wallet_type = \'hot\'')->execute([$amount, $userId]);
            $this->db->prepare('UPDATE withdrawal_queue SET status = \'approved\' WHERE id = ?')->execute([$id]);
        }

        $this->db->commit();
        $this->auditTrail?->append('user', (string)$userId, 'withdrawal_requested', 'withdrawal_queue', (string)$id, ['amount' => $amount, 'transaction_id' => $transactionId, 'cold_approval' => $needsColdApproval]);

        if ($this->kycService !== null && $this->kycService->shouldFlagHighRisk($userId)) {
            $this->db->prepare("INSERT INTO aml_flags (user_id, rule_code, severity, details) VALUES (?, 'high_risk_user', 'high', JSON_OBJECT('transaction_id', ?, 'reason', 'kyc_risk_threshold'))")
                ->execute([$userId, $transactionId]);
        }


        $this->logger->info('withdrawal_requested', [
            'user_id' => $userId,
            'tx_id' => $transactionId,
            'amount' => $amount,
            'region' => $region,
            'cold_approval' => $needsColdApproval,
        ]);

        return $id;
    }

    private function isReadOnlyMode(): bool
    {
        return $this->isControlEnabled('service_read_only');
    }

    private function isWithdrawalsDisabled(): bool
    {
        return $this->isControlEnabled('withdrawals_disabled');
    }

    private function isUserFrozen(int $userId): bool
    {
        $stmt = $this->db->prepare("SELECT is_frozen FROM user_restrictions WHERE user_id = ? LIMIT 1");
        $stmt->execute([$userId]);
        return (int)($stmt->fetchColumn() ?: 0) === 1;
    }

    private function isControlEnabled(string $controlName): bool
    {
        $stmt = $this->db->prepare('SELECT is_enabled FROM ops_controls WHERE control_name = ? LIMIT 1');
        $stmt->execute([$controlName]);
        return (int)($stmt->fetchColumn() ?: 0) === 1;
    }

    public function approveColdWithdrawal(int $queueId, string $approver): void
    {
        $this->db->prepare('UPDATE withdrawal_queue SET status=\'approved\', approved_by=?, approved_at=UTC_TIMESTAMP() WHERE id=? AND needs_cold_approval=1 AND status=\'pending\'')->execute([$approver, $queueId]);
        $this->auditTrail?->append('admin', $approver, 'withdrawal_approved', 'withdrawal_queue', (string)$queueId, ['queue_id' => $queueId]);
    }

    public function topUpHotFromCold(int $hotWalletUserId, int $coldWalletUserId, string $amount, string $idempotencyKey, string $approver, string $region = 'us-east-1', ?string $transactionId = null): void
    {
        $transactionId ??= self::newTransactionId();
        $this->db->beginTransaction();
        $this->db->prepare('INSERT INTO cold_wallet_topups (transaction_id, hot_wallet_user_id, cold_wallet_user_id, amount, status, approved_by, approved_at, idempotency_key, region) VALUES (?, ?, ?, ?, \'approved\', ?, UTC_TIMESTAMP(), ?, ?) ON DUPLICATE KEY UPDATE id=id')->execute([$transactionId, $hotWalletUserId, $coldWalletUserId, $amount, $approver, $idempotencyKey, $region]);
        $this->db->prepare('UPDATE wallets SET balance = balance - ? WHERE user_id = ? AND wallet_type = \'cold\'')->execute([$amount, $coldWalletUserId]);
        $this->db->prepare('UPDATE wallets SET balance = balance + ? WHERE user_id = ? AND wallet_type = \'hot\'')->execute([$amount, $hotWalletUserId]);
        $this->db->commit();
        $this->auditTrail?->append('admin', $approver, 'cold_to_hot_topup', 'wallet', (string)$hotWalletUserId, ['amount' => $amount, 'transaction_id' => $transactionId]);
    }

    private static function newTransactionId(): string
    {
        $bytes = random_bytes(16);
        $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
        $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
        return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($bytes), 4));
    }
}
