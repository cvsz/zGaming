<?php

declare(strict_types=1);

require_once __DIR__ . '/../audit/AuditTrail.php';

final class AdminAccess
{
    private const ROLE_PERMISSIONS = [
        'admin' => ['regulator:read', 'withdrawal:approve', 'audit:read'],
        'auditor' => ['regulator:read', 'audit:read'],
        'operator' => ['withdrawal:approve'],
    ];

    public function __construct(private readonly ?AuditTrail $auditTrail = null)
    {
    }

    public function authorize(string $role, string $permission, string $actorId, bool $hasTwoFactor, string $ipAddress): void
    {
        $allowedIps = array_filter(array_map('trim', explode(',', (string)getenv('ADMIN_IP_ALLOWLIST'))));
        if ($allowedIps !== [] && !in_array($ipAddress, $allowedIps, true)) {
            throw new RuntimeException('IP_NOT_ALLOWLISTED');
        }

        if ((bool)(getenv('ADMIN_2FA_REQUIRED') ?: false) && !$hasTwoFactor) {
            throw new RuntimeException('TWO_FACTOR_REQUIRED');
        }

        $permissions = self::ROLE_PERMISSIONS[$role] ?? [];
        if (!in_array($permission, $permissions, true)) {
            throw new RuntimeException('INSUFFICIENT_ROLE');
        }

        $this->auditTrail?->append('admin', $actorId, 'rbac_authorized', 'permission', $permission, ['role' => $role, 'ip' => $ipAddress]);
    }
}
