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
