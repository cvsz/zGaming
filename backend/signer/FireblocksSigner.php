<?php

declare(strict_types=1);

require_once __DIR__ . '/../interfaces/SignerInterface.php';
require_once __DIR__ . '/SigningAuditLogger.php';

final class FireblocksSigner implements SignerInterface
{
    public function __construct(
        private readonly string $vaultAccountId,
        private readonly string $keyId,
        private readonly string $address,
        private readonly ?SigningAuditLogger $auditLogger = null
    ) {
    }

    public function signTransaction(string $payload): string
    {
        $this->auditLogger?->logRequest('fireblocks_mock', $this->keyId, $payload);
        return sprintf('fireblocks_mock:%s:%s:%s', $this->vaultAccountId, $this->keyId, hash('sha256', $payload));
    }

    public function getAddress(): string
    {
        return $this->address;
    }

    public function verifySignature(string $payload, string $signature): bool
    {
        $expected = sprintf('fireblocks_mock:%s:%s:%s', $this->vaultAccountId, $this->keyId, hash('sha256', $payload));
        return hash_equals($expected, $signature);
    }
}
