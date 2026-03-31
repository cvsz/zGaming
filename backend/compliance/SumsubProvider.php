<?php

declare(strict_types=1);

require_once __DIR__ . '/../interfaces/KycProviderInterface.php';

final class SumsubProvider implements KycProviderInterface
{
    public function verifyUser(int $userId, array $profile): array
    {
        $countryRisk = in_array(strtoupper((string)($profile['country'] ?? '')), ['IR', 'KP', 'SY'], true) ? 90 : 20;
        $status = $countryRisk > 80 ? 'rejected' : 'verified';
        return [
            'status' => $status,
            'risk_score' => $countryRisk,
            'provider_ref' => 'sumsub-mock-' . $userId,
        ];
    }

    public function sanctionsCheck(int $userId, array $profile): bool
    {
        $name = strtoupper((string)($profile['full_name'] ?? ''));
        return !str_contains($name, 'SANCTIONED');
    }
}
