<?php

declare(strict_types=1);

require_once __DIR__ . '/common.php';

regulator_guard('audit:read');
[$page, $limit, $offset] = pagination();

$db = Database::conn();
$stmt = $db->prepare('SELECT id, actor_type, actor_id, action, entity_type, entity_id, payload_hash, prev_hash, hash, timestamp FROM audit_events ORDER BY id DESC LIMIT ? OFFSET ?');
$stmt->bindValue(1, $limit, PDO::PARAM_INT);
$stmt->bindValue(2, $offset, PDO::PARAM_INT);
$stmt->execute();

$rows = $stmt->fetchAll();
export_data($rows);
