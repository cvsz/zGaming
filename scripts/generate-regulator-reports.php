<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';

$date = $argv[1] ?? gmdate('Y-m-d');
$outDir = __DIR__ . '/../reports/regulator/' . $date;
if (!is_dir($outDir)) {
    mkdir($outDir, 0755, true);
}

$db = Database::conn();
$queries = [
    'transactions' => "SELECT transaction_id, tx_type, external_id, user_id, amount, currency, tx_timestamp, region FROM internal_transactions WHERE DATE(tx_timestamp)=? ORDER BY id",
    'aml_reports' => "SELECT report_ref, report_type, payload, created_at FROM aml_reports WHERE DATE(created_at)=? ORDER BY id",
    'audit_log' => "SELECT id, actor_type, actor_id, action, entity_type, entity_id, payload_hash, prev_hash, hash, timestamp FROM audit_events WHERE DATE(timestamp)=? ORDER BY id",
];

foreach ($queries as $name => $sql) {
    $stmt = $db->prepare($sql);
    $stmt->execute([$date]);
    $rows = $stmt->fetchAll();
    file_put_contents($outDir . '/' . $name . '.json', json_encode($rows, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR));
}

$snapshot = [
    'date' => $date,
    'generated_at' => gmdate(DATE_ATOM),
    'files' => [
        'transactions' => hash_file('sha256', $outDir . '/transactions.json'),
        'aml_reports' => hash_file('sha256', $outDir . '/aml_reports.json'),
        'audit_log' => hash_file('sha256', $outDir . '/audit_log.json'),
    ],
];
file_put_contents($outDir . '/snapshot.json', json_encode($snapshot, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR));

echo "regulator snapshots generated for {$date}\n";
