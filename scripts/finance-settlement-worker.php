<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';
require_once __DIR__ . '/../backend/finance/SettlementWorker.php';
require_once __DIR__ . '/../backend/audit/AuditTrail.php';

$region = getenv('WORKER_REGION') ?: 'us-east-1';
$loops = (int)(getenv('WORKER_LOOPS') ?: '100');
$sleepMicros = (int)(getenv('WORKER_IDLE_SLEEP_US') ?: '250000');

$db = Database::conn();
$worker = new SettlementWorker($db, $region, new AuditTrail($db));
for ($i = 0; $i < $loops; $i++) {
    $processed = $worker->runOnce();
    if (!$processed) {
        usleep($sleepMicros);
    }
}

echo "settlement worker complete\n";
