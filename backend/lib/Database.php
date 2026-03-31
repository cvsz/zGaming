<?php

declare(strict_types=1);

final class Database
{
    private static ?PDO $pdo = null;

    public static function conn(): PDO
    {
        if (self::$pdo instanceof PDO) {
            return self::$pdo;
        }

        $dsn = getenv('DB_DSN');
        if ($dsn === false || $dsn === '') {
            $host = getenv('DB_HOST') ?: '127.0.0.1';
            $name = getenv('DB_NAME') ?: 'casino';
            $port = getenv('DB_PORT') ?: '3306';
            $dsn = "mysql:host={$host};port={$port};dbname={$name};charset=utf8mb4";
        }

        $user = getenv('DB_USER') ?: 'casino';
        $pass = getenv('DB_PASSWORD') ?: (getenv('DB_PASS') ?: 'casino');
        self::$pdo = new PDO($dsn, $user, $pass, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);

        return self::$pdo;
    }
}
