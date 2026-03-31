<?php

declare(strict_types=1);

require_once __DIR__ . '/common.php';

regulator_guard('regulator:read');
[$page, $limit, $offset] = pagination();

$db = Database::conn();
$stmt = $db->prepare('SELECT report_ref, report_type, payload, created_at, exported_at FROM aml_reports ORDER BY id DESC LIMIT ? OFFSET ?');
$stmt->bindValue(1, $limit, PDO::PARAM_INT);
$stmt->bindValue(2, $offset, PDO::PARAM_INT);
$stmt->execute();

$rows = $stmt->fetchAll();
export_data($rows);
