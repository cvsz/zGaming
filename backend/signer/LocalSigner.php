<?php

declare(strict_types=1);

require_once __DIR__ . '/WalletSigner.php';
require_once __DIR__ . '/SigningAuditLogger.php';

final class LocalSigner implements WalletSigner
{
    public function __construct(
        private readonly string $keyId,
        private readonly string $address,
        private readonly string $devSecret,
        private readonly ?SigningAuditLogger $auditLogger = null
    ) {
    }

    public function signTransaction(string $unsignedPayload): string
    {
        $this->auditLogger?->logRequest('local_dev', $this->keyId, $unsignedPayload);
        return hash_hmac('sha256', $unsignedPayload, $this->devSecret);
    }

    public function getAddress(): string
    {
        return $this->address;
    }

    public function verifySignature(string $payload, string $signature): bool
    {
        return hash_equals($this->signTransaction($payload), $signature);
    }
}
