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
