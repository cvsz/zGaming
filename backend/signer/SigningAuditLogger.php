<?php

declare(strict_types=1);

final class SigningAuditLogger
{
    private string $logFile;

    public function __construct(?string $logFile = null)
    {
        $this->logFile = $logFile ?? (__DIR__ . '/../storage/signing/audit.log');
    }

    public function logRequest(string $provider, string $keyId, string $payload): void
    {
        $dir = dirname($this->logFile);
        if (!is_dir($dir)) {
            mkdir($dir, 0700, true);
        }

        $entry = [
            'ts' => gmdate(DATE_ATOM),
            'provider' => $provider,
            'key_id' => $keyId,
            'payload_hash' => hash('sha256', $payload),
        ];

        file_put_contents($this->logFile, json_encode($entry, JSON_THROW_ON_ERROR) . PHP_EOL, FILE_APPEND | LOCK_EX);
    }
}
