<?php

declare(strict_types=1);

interface KycProviderInterface
{
    /** @return array{status:string,risk_score:int,provider_ref:string} */
    public function verifyUser(int $userId, array $profile): array;

    public function sanctionsCheck(int $userId, array $profile): bool;
}
