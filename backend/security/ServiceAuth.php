<?php

declare(strict_types=1);

require_once __DIR__ . '/../lib/auth.php';

final class ServiceAuth
{
    /** @param array<string,string> $serviceSecrets */
    public function __construct(private readonly array $serviceSecrets, private readonly int $maxTtlSeconds = 300)
    {
    }

    public function mintToken(string $serviceId, string $audience): string
    {
        if (!isset($this->serviceSecrets[$serviceId])) {
            throw new RuntimeException('UNKNOWN_SERVICE');
        }

        $now = time();
        $claims = [
            'iss' => $serviceId,
            'sub' => $serviceId,
            'aud' => $audience,
            'iat' => $now,
            'exp' => $now + $this->maxTtlSeconds,
            'service_id' => $serviceId,
        ];

        return jwt_sign($claims, $this->serviceSecrets[$serviceId]);
    }

    /** @return array<string,mixed> */
    public function verifyIncoming(string $token, string $expectedAudience): array
    {
        [$header64, $payload64, $sig64] = explode('.', $token, 3) + [null, null, null];
        if ($header64 === null || $payload64 === null || $sig64 === null) {
            throw new RuntimeException('UNSIGNED_OR_MALFORMED_TOKEN');
        }

        $payload = json_decode((string)base64_decode(strtr($payload64, '-_', '+/')), true, 512, JSON_THROW_ON_ERROR);
        $issuer = (string)($payload['iss'] ?? '');
        if ($issuer === '' || !isset($this->serviceSecrets[$issuer])) {
            throw new RuntimeException('UNKNOWN_SERVICE');
        }

        $expectedSig = base64url_encode(hash_hmac('sha256', $header64 . '.' . $payload64, $this->serviceSecrets[$issuer], true));
        if (!hash_equals($expectedSig, $sig64)) {
            throw new RuntimeException('INVALID_SIGNATURE');
        }

        $now = time();
        if ((int)($payload['exp'] ?? 0) < $now || ((int)($payload['iat'] ?? 0) + $this->maxTtlSeconds) < $now) {
            throw new RuntimeException('TOKEN_EXPIRED');
        }

        if ((string)($payload['aud'] ?? '') !== $expectedAudience) {
            throw new RuntimeException('INVALID_AUDIENCE');
        }

        return $payload;
    }
}

/** @return array<string,string> */
function parse_service_secrets_env(string $raw): array
{
    $result = [];
    foreach (array_filter(array_map('trim', explode(',', $raw))) as $pair) {
        [$serviceId, $secret] = explode(':', $pair, 2) + ['', ''];
        if ($serviceId !== '' && $secret !== '') {
            $result[$serviceId] = $secret;
        }
    }
    return $result;
}

function require_service_auth(string $audience): array
{
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!str_starts_with($header, 'Bearer ')) {
        json_response(401, ['error' => 'UNSIGNED_REQUEST']);
    }

    $services = parse_service_secrets_env((string)getenv('SERVICE_SHARED_SECRETS'));
    $auth = new ServiceAuth($services, min(300, (int)(getenv('SERVICE_TOKEN_TTL') ?: '300')));

    try {
        return $auth->verifyIncoming(substr($header, 7), $audience);
    } catch (Throwable $e) {
        json_response(401, ['error' => $e->getMessage()]);
    }
}
