<?php

declare(strict_types=1);

require_once __DIR__ . '/../../lib/auth.php';
require_once __DIR__ . '/../../lib/Database.php';
require_once __DIR__ . '/../../security/ServiceAuth.php';
require_once __DIR__ . '/../../audit/AuditTrail.php';
require_once __DIR__ . '/../../security/AdminAccess.php';

function regulator_guard(string $permission): void
{
    require_service_auth('regulator-api');

    $role = (string)($_SERVER['HTTP_X_ROLE'] ?? 'auditor');
    $actorId = (string)($_SERVER['HTTP_X_ACTOR_ID'] ?? 'system-regulator');
    $hasTwoFactor = (($_SERVER['HTTP_X_2FA'] ?? '0') === '1');
    $ip = (string)($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');

    $access = new AdminAccess(new AuditTrail(Database::conn()));
    $access->authorize($role, $permission, $actorId, $hasTwoFactor, $ip);
}

function pagination(): array
{
    $page = max(1, (int)($_GET['page'] ?? 1));
    $limit = min(250, max(1, (int)($_GET['limit'] ?? 50)));
    return [$page, $limit, ($page - 1) * $limit];
}

function export_data(array $rows): void
{
    $format = strtolower((string)($_GET['format'] ?? 'json'));
    if ($format === 'csv') {
        header('Content-Type: text/csv; charset=utf-8');
        $out = fopen('php://output', 'wb');
        if ($rows !== []) {
            fputcsv($out, array_keys($rows[0]));
            foreach ($rows as $row) {
                fputcsv($out, $row);
            }
        }
        fclose($out);
        exit;
    }

    json_response(200, ['data' => $rows]);
}
