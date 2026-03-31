<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';
require_once __DIR__ . '/../backend/finance/ReconciliationEngine.php';

$date = $argv[1] ?? gmdate('Y-m-d', time() - 86400);
$engine = new ReconciliationEngine(Database::conn());
$engine->runForDate($date);

echo "reconciliation complete for {$date}\n";
