<?php

declare(strict_types=1);

require_once __DIR__ . '/../audit/AuditTrail.php';
require_once __DIR__ . '/../observability/StructuredLogger.php';

final class SettlementWorker
{
    private readonly StructuredLogger $logger;
    public function __construct(private readonly PDO $db, private readonly string $region, private readonly ?AuditTrail $auditTrail = null)
    {
        $this->logger = new StructuredLogger('settlement-worker');
    }

    public function runOnce(): bool
    {
        $this->db->beginTransaction();
        $stmt = $this->db->prepare("SELECT id, transaction_id, type, payload, retries, idempotency_key FROM settlement_queue WHERE status='pending' AND retries < 5 ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED");
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
            $this->logger->info('settlement_processed', ['queue_id' => (int)$job['id'], 'tx_id' => (string)$job['transaction_id'], 'region' => $this->region]);
        } catch (Throwable $e) {
            $this->db->prepare("UPDATE settlement_queue SET status='pending', retries=retries+1, last_error=? WHERE id=?")->execute([substr($e->getMessage(), 0, 250), $job['id']]);
            $this->logger->error('settlement_failed', ['queue_id' => (int)$job['id'], 'tx_id' => (string)$job['transaction_id'], 'error' => substr($e->getMessage(), 0, 250), 'region' => $this->region]);
        }

        return true;
    }

    private function processJob(array $job): void
    {
        $payload = json_decode((string)$job['payload'], true, 512, JSON_THROW_ON_ERROR);
        $transactionId = (string)($job['transaction_id'] ?: ($payload['transaction_id'] ?? $job['idempotency_key']));
        $this->db->prepare('INSERT INTO internal_transactions (transaction_id, tx_type, external_id, user_id, amount, tx_timestamp, region, metadata) VALUES (?, ?, ?, ?, ?, UTC_TIMESTAMP(), ?, ?) ON DUPLICATE KEY UPDATE external_id=external_id')
            ->execute([$transactionId, $job['type'], $job['idempotency_key'], $payload['user_id'] ?? null, $payload['amount'] ?? '0', $this->region, json_encode($payload, JSON_THROW_ON_ERROR)]);
        $this->auditTrail?->append('system', 'settlement-worker', 'settlement_processed', 'settlement_queue', (string)$job['id'], ['transaction_id' => $transactionId, 'type' => $job['type']]);
    }
}
