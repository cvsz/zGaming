<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';

$action = $argv[1] ?? '';
$actor = $argv[2] ?? 'incident-operator';
$target = $argv[3] ?? null;

$db = Database::conn();

switch ($action) {
    case 'freeze-global':
        setControl($db, 'withdrawals_disabled', 1, $actor, 'global emergency freeze');
        break;
    case 'unfreeze-global':
        setControl($db, 'withdrawals_disabled', 0, $actor, 'global emergency unfreeze');
        break;
    case 'withdrawals-off':
        setControl($db, 'withdrawals_disabled', 1, $actor, 'withdrawals disabled');
        break;
    case 'withdrawals-on':
        setControl($db, 'withdrawals_disabled', 0, $actor, 'withdrawals enabled');
        break;
    case 'read-only-on':
        setControl($db, 'service_read_only', 1, $actor, 'service isolation read-only mode');
        break;
    case 'read-only-off':
        setControl($db, 'service_read_only', 0, $actor, 'service exited read-only mode');
        break;
    case 'freeze-user':
        if ($target === null) {
            throw new InvalidArgumentException('freeze-user requires user id');
        }
        setUserFreeze($db, (int)$target, 1, $actor, 'user freeze');
        break;
    case 'unfreeze-user':
        if ($target === null) {
            throw new InvalidArgumentException('unfreeze-user requires user id');
        }
        setUserFreeze($db, (int)$target, 0, $actor, 'user unfreeze');
        break;
    default:
        throw new InvalidArgumentException('Unknown action');
}

echo "ok action={$action}\n";

function setControl(PDO $db, string $name, int $enabled, string $actor, string $reason): void
{
    $db->prepare('INSERT INTO ops_controls (control_name, is_enabled, updated_by, updated_at) VALUES (?, ?, ?, UTC_TIMESTAMP()) ON DUPLICATE KEY UPDATE is_enabled=VALUES(is_enabled), updated_by=VALUES(updated_by), updated_at=UTC_TIMESTAMP()')
        ->execute([$name, $enabled, $actor]);
    $db->prepare('INSERT INTO emergency_actions (actor_id, action, target_type, target_id, reason, metadata) VALUES (?, ?, ?, ?, ?, JSON_OBJECT("enabled", ?))')
        ->execute([$actor, $name, 'global_control', $name, $reason, $enabled]);
}

function setUserFreeze(PDO $db, int $userId, int $enabled, string $actor, string $reason): void
{
    $db->prepare('INSERT INTO user_restrictions (user_id, is_frozen, reason, updated_by, updated_at) VALUES (?, ?, ?, ?, UTC_TIMESTAMP()) ON DUPLICATE KEY UPDATE is_frozen=VALUES(is_frozen), reason=VALUES(reason), updated_by=VALUES(updated_by), updated_at=UTC_TIMESTAMP()')
        ->execute([$userId, $enabled, $reason, $actor]);
    $db->prepare('INSERT INTO emergency_actions (actor_id, action, target_type, target_id, reason, metadata) VALUES (?, ?, ?, ?, ?, JSON_OBJECT("enabled", ?))')
        ->execute([$actor, $enabled ? 'freeze_user' : 'unfreeze_user', 'user', (string)$userId, $reason, $enabled]);
}
