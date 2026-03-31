<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';

$dateFrom = $argv[1] ?? gmdate('Y-m-d', time() - 86400);
$dateTo = $argv[2] ?? gmdate('Y-m-d');
$out = $argv[3] ?? (__DIR__ . '/../reports/regulator/transactions-' . $dateFrom . '-' . $dateTo . '.json');

$db = Database::conn();
$stmt = $db->prepare('SELECT transaction_id, tx_type, external_id, user_id, amount, currency, tx_timestamp, region, metadata FROM internal_transactions WHERE DATE(tx_timestamp) BETWEEN ? AND ? ORDER BY tx_timestamp ASC, id ASC');
$stmt->execute([$dateFrom, $dateTo]);
file_put_contents($out, json_encode($stmt->fetchAll(), JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR));

echo "transaction_export={$out}\n";
