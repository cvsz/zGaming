<?php

declare(strict_types=1);

require_once __DIR__ . '/../interfaces/KycProviderInterface.php';

final class OnfidoProvider implements KycProviderInterface
{
    public function verifyUser(int $userId, array $profile): array
    {
        $docType = strtolower((string)($profile['document_type'] ?? 'unknown'));
        $risk = $docType === 'passport' ? 15 : 45;
        return [
            'status' => $risk >= 70 ? 'rejected' : 'verified',
            'risk_score' => $risk,
            'provider_ref' => 'onfido-mock-' . $userId,
        ];
    }

    public function sanctionsCheck(int $userId, array $profile): bool
    {
        $email = strtolower((string)($profile['email'] ?? ''));
        return !str_ends_with($email, '.blocked');
    }
}
