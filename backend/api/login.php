<?php

declare(strict_types=1);

require_once __DIR__ . '/../lib/auth.php';

function consume_nonce(string $nonceHash, int $issuedAt, int $ttlSeconds): bool
{
    $storageDir = __DIR__ . '/../storage/auth';
    $nonceFile = $storageDir . '/used_nonces.log';
    if (!is_dir($storageDir) && !mkdir($storageDir, 0700, true) && !is_dir($storageDir)) {
        throw new RuntimeException('FAILED_TO_CREATE_NONCE_STORAGE');
    }

    $handle = fopen($nonceFile, 'c+');
    if ($handle === false) {
        throw new RuntimeException('FAILED_TO_OPEN_NONCE_STORAGE');
    }

    try {
        if (!flock($handle, LOCK_EX)) {
            throw new RuntimeException('FAILED_TO_LOCK_NONCE_STORAGE');
        }

        $now = time();
        $minIssuedAt = $now - $ttlSeconds;
        $freshLines = [];
        $isReplay = false;

        rewind($handle);
        while (($line = fgets($handle)) !== false) {
            $line = trim($line);
            if ($line === '') {
                continue;
            }
            [$existingHash, $existingIssuedAt] = explode(',', $line, 2) + ['', '0'];
            $existingIssuedAtInt = (int)$existingIssuedAt;
            if ($existingIssuedAtInt < $minIssuedAt) {
                continue;
            }
            if ($existingHash === $nonceHash) {
                $isReplay = true;
            }
            $freshLines[] = "{$existingHash},{$existingIssuedAtInt}";
        }

        if ($isReplay) {
            return false;
        }

        $freshLines[] = "{$nonceHash},{$issuedAt}";

        ftruncate($handle, 0);
        rewind($handle);
        fwrite($handle, implode(PHP_EOL, $freshLines) . PHP_EOL);

        return true;
    } finally {
        flock($handle, LOCK_UN);
        fclose($handle);
    }
}

/**
 * Stateless SIWE-like login endpoint with deterministic nonce validation.
 *
 * Required envs:
 * - JWT_SECRET
 * - SESSION_TTL_SECONDS (default 300)
 */

try {
    $body = read_json_input();

    $walletAddress = (string)($body['walletAddress'] ?? '');
    $chain = (string)($body['chain'] ?? '');
    $nonce = (string)($body['nonce'] ?? '');
    $issuedAt = (int)($body['issuedAt'] ?? 0);
    $signature = (string)($body['signature'] ?? '');
    $chainId = (int)($body['chainId'] ?? 0);
    $role = (string)($body['role'] ?? 'player');

    if ($walletAddress === '' || $nonce === '' || $signature === '' || $chain === '' || $issuedAt <= 0) {
        json_response(422, ['error' => 'MISSING_REQUIRED_FIELDS']);
    }

    if (!in_array($chain, ['eth', 'sol'], true)) {
        json_response(422, ['error' => 'UNSUPPORTED_CHAIN']);
    }

    $allowedRoles = ['player', 'admin', 'operator', 'auditor'];
    if (!in_array($role, $allowedRoles, true)) {
        json_response(422, ['error' => 'INVALID_ROLE']);
    }

    $ttlSeconds = (int)auth_env('SESSION_TTL_SECONDS', '300');
    $clockSkewSeconds = 15;
    $now = time();

    if ($issuedAt > $now + $clockSkewSeconds) {
        json_response(401, ['error' => 'INVALID_ISSUED_AT_FUTURE']);
    }

    if (($now - $issuedAt) > $ttlSeconds) {
        json_response(401, ['error' => 'SESSION_EXPIRED']);
    }

    // Deterministic anti-replay nonce validation.
    if (!preg_match('/^[A-Za-z0-9_-]{16,128}$/', $nonce)) {
        json_response(401, ['error' => 'INVALID_NONCE_FORMAT']);
    }

    // SIWE-like message canonicalization and deterministic signature check.
    $canonical = implode('|', [
        'zgaming-login-v1',
        strtolower($walletAddress),
        $chain,
        (string)$chainId,
        $nonce,
        (string)$issuedAt,
        $role,
    ]);

    $walletAuthSecret = auth_env('WALLET_AUTH_SECRET', auth_env('JWT_SECRET'));
    $expectedSignature = hash_hmac('sha256', $canonical, $walletAuthSecret);

    if (!hash_equals($expectedSignature, $signature)) {
        json_response(401, ['error' => 'INVALID_SIGNATURE']);
    }

    $nonceHash = hash_nonce($nonce);
    if (!consume_nonce($nonceHash, $issuedAt, $ttlSeconds)) {
        json_response(409, ['error' => 'NONCE_REPLAY_DETECTED']);
    }

    $jwtSecret = auth_env('JWT_SECRET');
    $exp = $now + $ttlSeconds;

    $claims = [
        'iss' => 'zgaming-auth',
        'sub' => strtolower($walletAddress),
        'aud' => 'zgaming-platform',
        'iat' => $now,
        'exp' => $exp,
        'nbf' => $now - $clockSkewSeconds,
        'jti' => $nonceHash,
        'chain' => $chain,
        'chainId' => $chainId,
        'role' => $role,
        'two_factor_enabled' => (($body['twoFactorEnabled'] ?? false) === true),
        'scope' => ['wallet:transfer', 'ledger:read'],
    ];

    $token = jwt_sign($claims, $jwtSecret);

    json_response(200, [
        'tokenType' => 'Bearer',
        'accessToken' => $token,
        'expiresAt' => gmdate(DATE_ATOM, $exp),
        'session' => [
            'subject' => strtolower($walletAddress),
            'chain' => $chain,
            'chainId' => $chainId,
            'nonceHash' => $nonceHash,
        ],
    ]);
} catch (JsonException) {
    json_response(400, ['error' => 'INVALID_JSON']);
} catch (Throwable $exception) {
    json_response(500, [
        'error' => 'INTERNAL_ERROR',
        'message' => $exception->getMessage(),
    ]);
}
