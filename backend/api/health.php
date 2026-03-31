<?php

declare(strict_types=1);

require_once __DIR__ . '/../lib/auth.php';

json_response(200, [
    'status' => 'ok',
    'service' => 'backend-api',
    'timestamp' => gmdate(DATE_ATOM),
]);
