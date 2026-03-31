<?php

declare(strict_types=1);

final class AuditTrail
{
    public function __construct(private readonly PDO $db)
    {
    }

    public function append(string $actorType, string $actorId, string $action, string $entityType, string $entityId, array $payload): void
    {
        $payloadJson = json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        $payloadHash = hash('sha256', $payloadJson);
        $prevHash = (string)($this->db->query('SELECT hash FROM audit_events ORDER BY id DESC LIMIT 1')->fetchColumn() ?: str_repeat('0', 64));
        $timestamp = gmdate('Y-m-d H:i:s');
        $hashInput = implode('|', [$actorType, $actorId, $action, $entityType, $entityId, $payloadHash, $prevHash, $timestamp]);
        $eventHash = hash('sha256', $hashInput);

        $this->db->prepare('INSERT INTO audit_events (actor_type, actor_id, action, entity_type, entity_id, payload_hash, prev_hash, hash, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
            ->execute([$actorType, $actorId, $action, $entityType, $entityId, $payloadHash, $prevHash, $eventHash, $timestamp]);
    }
}
