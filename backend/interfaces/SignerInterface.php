<?php

declare(strict_types=1);

interface SignerInterface
{
    public function signTransaction(string $payload): string;

    public function getAddress(): string;

    public function verifySignature(string $payload, string $signature): bool;
}
