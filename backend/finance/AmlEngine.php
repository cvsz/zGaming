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
        $this->flagKycRisk($userId);
    }

    private function flagLargeTransactions(int $userId): void
    {
        $stmt = $this->db->prepare("SELECT id, transaction_id, amount FROM internal_transactions WHERE user_id=? AND amount > 10000 ORDER BY id DESC LIMIT 20");
        $stmt->execute([$userId]);
        foreach ($stmt->fetchAll() as $row) {
            $this->createFlag($userId, 'large_transaction', 'high', ['amount' => $row['amount'], 'transaction_id' => $row['transaction_id']], (int)$row['id']);
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

    private function flagKycRisk(int $userId): void
    {
        $stmt = $this->db->prepare('SELECT risk_score, sanctions_clear FROM user_compliance WHERE user_id=? LIMIT 1');
        $stmt->execute([$userId]);
        $row = $stmt->fetch();
        if (!$row) {
            return;
        }

        if ((int)$row['risk_score'] >= 75 || (int)$row['sanctions_clear'] !== 1) {
            $this->createFlag($userId, 'kyc_risk', 'high', ['risk_score' => (int)$row['risk_score'], 'sanctions_clear' => (int)$row['sanctions_clear']], null);
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
