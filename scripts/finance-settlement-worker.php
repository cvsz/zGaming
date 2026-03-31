<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';
require_once __DIR__ . '/../backend/finance/SettlementWorker.php';

$region = getenv('WORKER_REGION') ?: 'us-east-1';
$loops = (int)(getenv('WORKER_LOOPS') ?: '100');
$sleepMicros = (int)(getenv('WORKER_IDLE_SLEEP_US') ?: '250000');

$worker = new SettlementWorker(Database::conn(), $region);
for ($i = 0; $i < $loops; $i++) {
    $processed = $worker->runOnce();
    if (!$processed) {
        usleep($sleepMicros);
    }
}

echo "settlement worker complete\n";
