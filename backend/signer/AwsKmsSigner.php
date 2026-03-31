<?php

declare(strict_types=1);

require_once __DIR__ . '/../interfaces/SignerInterface.php';
require_once __DIR__ . '/SigningAuditLogger.php';

final class AwsKmsSigner implements SignerInterface
{
    public function __construct(
        private readonly string $keyId,
        private readonly string $address,
        private readonly ?SigningAuditLogger $auditLogger = null
    ) {
    }

    public function signTransaction(string $payload): string
    {
        $this->auditLogger?->logRequest('aws_kms_mock', $this->keyId, $payload);
        return sprintf('aws_kms_mock:%s:%s', $this->keyId, hash('sha256', $payload));
    }

    public function getAddress(): string
    {
        return $this->address;
    }

    public function verifySignature(string $payload, string $signature): bool
    {
        $expected = sprintf('aws_kms_mock:%s:%s', $this->keyId, hash('sha256', $payload));
        return hash_equals($expected, $signature);
    }
}
