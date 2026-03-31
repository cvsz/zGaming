<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';

$db = Database::conn();
$rows = $db->query('SELECT id, actor_type, actor_id, action, entity_type, entity_id, payload_hash, prev_hash, hash, timestamp FROM audit_events ORDER BY id ASC')->fetchAll();

$prev = str_repeat('0', 64);
foreach ($rows as $row) {
    if ((string)$row['prev_hash'] !== $prev) {
        fwrite(STDERR, 'audit_chain_error=prev_hash_mismatch id=' . $row['id'] . PHP_EOL);
        exit(2);
    }

    $expected = hash('sha256', implode('|', [$row['actor_type'], $row['actor_id'], $row['action'], $row['entity_type'], $row['entity_id'], $row['payload_hash'], $row['prev_hash'], $row['timestamp']]));
    if (!hash_equals($expected, (string)$row['hash'])) {
        fwrite(STDERR, 'audit_chain_error=hash_mismatch id=' . $row['id'] . PHP_EOL);
        exit(2);
    }

    $prev = (string)$row['hash'];
}

echo 'audit_chain_status=pass total_events=' . count($rows) . PHP_EOL;
