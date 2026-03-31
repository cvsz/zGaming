<?php

declare(strict_types=1);

interface WalletSigner
{
    public function signTransaction(string $unsignedPayload): string;

    public function getAddress(): string;
}
