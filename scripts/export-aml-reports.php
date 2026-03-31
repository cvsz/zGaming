<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';

$dateFrom = $argv[1] ?? gmdate('Y-m-d', time() - 86400);
$dateTo = $argv[2] ?? gmdate('Y-m-d');
$out = $argv[3] ?? (__DIR__ . '/../reports/regulator/aml-reports-' . $dateFrom . '-' . $dateTo . '.json');

$db = Database::conn();
$stmt = $db->prepare('SELECT report_ref, report_type, payload, created_at, exported_at FROM aml_reports WHERE DATE(created_at) BETWEEN ? AND ? ORDER BY id ASC');
$stmt->execute([$dateFrom, $dateTo]);
$rows = $stmt->fetchAll();
file_put_contents($out, json_encode($rows, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR));
$db->prepare('UPDATE aml_reports SET exported_at = UTC_TIMESTAMP() WHERE DATE(created_at) BETWEEN ? AND ?')->execute([$dateFrom, $dateTo]);

echo "aml_export={$out}\n";
