<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';

$db = Database::conn();
$alerts = [];

$failedTx = (int)($db->query("SELECT COUNT(*) FROM settlement_queue WHERE status='pending' AND retries >= 3")->fetchColumn() ?: 0);
if ($failedTx >= 10) {
    $alerts[] = ['severity' => 'high', 'alert' => 'repeated_transaction_failures', 'count' => $failedTx];
}

$reconMismatch = (int)($db->query("SELECT COUNT(*) FROM reconciliation_report WHERE status='open'")->fetchColumn() ?: 0);
if ($reconMismatch > 0) {
    $alerts[] = ['severity' => 'critical', 'alert' => 'reconciliation_mismatch', 'count' => $reconMismatch];
}

$activitySpike = (int)($db->query("SELECT COUNT(*) FROM internal_transactions WHERE tx_timestamp >= (UTC_TIMESTAMP() - INTERVAL 5 MINUTE)")->fetchColumn() ?: 0);
if ($activitySpike >= 500) {
    $alerts[] = ['severity' => 'medium', 'alert' => 'abnormal_activity_spike', 'count' => $activitySpike];
}

echo json_encode(['alerts' => $alerts], JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR) . PHP_EOL;
exit($alerts === [] ? 0 : 1);
