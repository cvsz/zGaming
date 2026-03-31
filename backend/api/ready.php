<?php

declare(strict_types=1);

require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../lib/Database.php';

try {
    $db = Database::conn();
    $db->query('SELECT 1');
    json_response(200, [
        'status' => 'ready',
        'checks' => [
            'db' => 'ok',
        ],
        'timestamp' => gmdate(DATE_ATOM),
    ]);
} catch (Throwable $e) {
    json_response(503, [
        'status' => 'not_ready',
        'checks' => [
            'db' => 'failed',
        ],
        'error' => substr($e->getMessage(), 0, 200),
        'timestamp' => gmdate(DATE_ATOM),
    ]);
}
