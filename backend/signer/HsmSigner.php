<?php

declare(strict_types=1);

final class HsmSigner implements WalletSigner
{
    public function __construct(private readonly string $keyHandle, private readonly string $address)
    {
    }

    public function signTransaction(string $unsignedPayload): string
    {
        return sprintf('hsm_stub:%s:%s', $this->keyHandle, hash('sha256', $unsignedPayload));
    }

    public function getAddress(): string
    {
        return $this->address;
    }
}
