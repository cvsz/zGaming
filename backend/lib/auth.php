<?php

declare(strict_types=1);

function auth_env(string $key, ?string $default = null): string
{
    $value = getenv($key);
    if ($value === false || $value === '') {
        if ($default !== null) {
            return $default;
        }
        throw new RuntimeException("Missing required env: {$key}");
    }

    return $value;
}

function base64url_encode(string $data): string
{
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function jwt_sign(array $payload, string $secret): string
{
    $header = ['alg' => 'HS256', 'typ' => 'JWT'];
    $headerEncoded = base64url_encode(json_encode($header, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
    $payloadEncoded = base64url_encode(json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
    $signingInput = "{$headerEncoded}.{$payloadEncoded}";
    $signature = hash_hmac('sha256', $signingInput, $secret, true);

    return "{$signingInput}." . base64url_encode($signature);
}

function hash_nonce(string $nonce): string
{
    return hash('sha256', $nonce);
}

function read_json_input(): array
{
    $raw = file_get_contents('php://input') ?: '{}';

    /** @var array<string,mixed> $decoded */
    $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
    return $decoded;
}

function json_response(int $status, array $payload): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    exit;
}
