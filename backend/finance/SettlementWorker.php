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
