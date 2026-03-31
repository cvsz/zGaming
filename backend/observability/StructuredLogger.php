<?php

declare(strict_types=1);

final class StructuredLogger
{
    public function __construct(private readonly string $service)
    {
    }

    public function info(string $event, array $context = []): void
    {
        $this->log('INFO', $event, $context);
    }

    public function warning(string $event, array $context = []): void
    {
        $this->log('WARN', $event, $context);
    }

    public function error(string $event, array $context = []): void
    {
        $this->log('ERROR', $event, $context);
    }

    private function log(string $level, string $event, array $context): void
    {
        $record = [
            'timestamp' => gmdate(DATE_ATOM),
            'level' => $level,
            'service' => $this->service,
            'event' => $event,
            'context' => $context,
        ];

        error_log((string)json_encode($record, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
    }
}
