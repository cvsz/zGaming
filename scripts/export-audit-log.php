<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';

$dateFrom = $argv[1] ?? gmdate('Y-m-d', time() - 86400);
$dateTo = $argv[2] ?? gmdate('Y-m-d');
$out = $argv[3] ?? (__DIR__ . '/../reports/regulator/audit-log-' . $dateFrom . '-' . $dateTo . '.json');

$db = Database::conn();
$stmt = $db->prepare('SELECT id, actor_type, actor_id, action, entity_type, entity_id, payload_hash, prev_hash, hash, timestamp FROM audit_events WHERE DATE(timestamp) BETWEEN ? AND ? ORDER BY id ASC');
$stmt->execute([$dateFrom, $dateTo]);
file_put_contents($out, json_encode($stmt->fetchAll(), JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR));

echo "audit_export={$out}\n";
