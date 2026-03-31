<?php

declare(strict_types=1);

require_once __DIR__ . '/../interfaces/KycProviderInterface.php';

final class KycService
{
    public function __construct(private readonly PDO $db, private readonly KycProviderInterface $provider)
    {
    }

    public function assessUser(int $userId, array $profile): void
    {
        $result = $this->provider->verifyUser($userId, $profile);
        $sanctionsPassed = $this->provider->sanctionsCheck($userId, $profile);
        $status = $sanctionsPassed ? $result['status'] : 'rejected';
        $riskScore = $sanctionsPassed ? (int)$result['risk_score'] : 100;

        $this->db->prepare('INSERT INTO user_compliance (user_id, kyc_status, risk_score, sanctions_clear, kyc_provider, provider_ref, updated_at) VALUES (?, ?, ?, ?, ?, ?, UTC_TIMESTAMP()) ON DUPLICATE KEY UPDATE kyc_status=VALUES(kyc_status), risk_score=VALUES(risk_score), sanctions_clear=VALUES(sanctions_clear), kyc_provider=VALUES(kyc_provider), provider_ref=VALUES(provider_ref), updated_at=UTC_TIMESTAMP()')
            ->execute([$userId, $status, $riskScore, $sanctionsPassed ? 1 : 0, get_class($this->provider), (string)$result['provider_ref']]);
    }

    public function isWithdrawalAllowed(int $userId): bool
    {
        $stmt = $this->db->prepare("SELECT kyc_status FROM user_compliance WHERE user_id = ? LIMIT 1");
        $stmt->execute([$userId]);
        return $stmt->fetchColumn() === 'verified';
    }

    public function shouldFlagHighRisk(int $userId): bool
    {
        $stmt = $this->db->prepare('SELECT risk_score FROM user_compliance WHERE user_id = ? LIMIT 1');
        $stmt->execute([$userId]);
        $score = (int)($stmt->fetchColumn() ?: 0);
        return $score >= 75;
    }
}
