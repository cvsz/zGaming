<?php

declare(strict_types=1);

final class LocalSigner implements WalletSigner
{
    public function __construct(private readonly string $privateKey, private readonly string $address)
    {
    }

    public function signTransaction(string $unsignedPayload): string
    {
        return hash_hmac('sha256', $unsignedPayload, $this->privateKey);
    }

    public function getAddress(): string
    {
        return $this->address;
    }
}
