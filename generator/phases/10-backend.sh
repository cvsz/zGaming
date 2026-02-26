#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
# ============================================================
# PHASE 10 – BACKEND CORE (API / DB / BASE STRUCTURE)
# ============================================================

echo "[PHASE 10] BACKEND – Core API & Database Setup"

# ------------------------------------------------------------
# Resolve ROOT (DO NOT TRUST PWD)
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKEND_DIR="$ROOT/backend"

# ------------------------------------------------------------
# Create backend directory if missing
# ------------------------------------------------------------
if [[ ! -d "$BACKEND_DIR" ]]; then
  echo "📁 Creating backend directory"
  mkdir -p "$BACKEND_DIR"
fi

cd "$BACKEND_DIR"

# ------------------------------------------------------------
# Create base structure (idempotent)
# ------------------------------------------------------------
echo "📁 Creating backend structure"

mkdir -p \
  api \
  core \
  modules \
  middleware \
  wallet \
  providers \
  compliance \
  storage/logs \
  storage/ledger \
  storage/audit \
  db/migrations \
  db/seeds

# ------------------------------------------------------------
# .env (only if not exists)
# ------------------------------------------------------------
if [[ ! -f ".env" ]]; then
  echo "🔐 Creating backend .env"
  cat > .env <<'EOF'
APP_ENV=production
APP_KEY=change-me
APP_DEBUG=false

DB_HOST=db
DB_PORT=3306
DB_NAME=casino
DB_USER=casino
DB_PASS=casino

JWT_SECRET=change-me
JWT_TTL=3600

BASE_CURRENCY=EUR
ALLOWED_CURRENCIES=EUR,USD,THB

LOG_LEVEL=info
EOF
else
  echo "ℹ️ backend .env already exists – skipped"
fi

# ------------------------------------------------------------
# composer.json (minimal but real)
# ------------------------------------------------------------
if [[ ! -f "composer.json" ]]; then
  echo "📦 Creating composer.json"
  cat > composer.json <<'EOF'
{
  "require": {
    "php": "^8.3",
    "firebase/php-jwt": "^6.11",
    "ramsey/uuid": "^4.9",
    "monolog/monolog": "^3.9"
  },
  "autoload": {
    "psr-4": {
      "App\\": "core/"
    }
  }
}
EOF
fi

# ------------------------------------------------------------
# Core bootstrap
# ------------------------------------------------------------
if [[ ! -f "core/Bootstrap.php" ]]; then
  cat > core/Bootstrap.php <<'EOF'
<?php
declare(strict_types=1);

use Monolog\Logger;
use Monolog\Handler\StreamHandler;

require __DIR__ . '/../vendor/autoload.php';

date_default_timezone_set('UTC');

$log = new Logger('casino');
$log->pushHandler(new StreamHandler(__DIR__ . '/../storage/logs/app.log'));

return [
    'log' => $log,
];
EOF
fi

# ------------------------------------------------------------
# Database connection
# ------------------------------------------------------------
if [[ ! -f "core/Database.php" ]]; then
  cat > core/Database.php <<'EOF'
<?php
declare(strict_types=1);

namespace App;

use PDO;

final class Database
{
    public static function connect(): PDO
    {
        $dsn = sprintf(
            "mysql:host=%s;dbname=%s;charset=utf8mb4",
            getenv('DB_HOST'),
            getenv('DB_NAME')
        );

        return new PDO(
            $dsn,
            getenv('DB_USER'),
            getenv('DB_PASS'),
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]
        );
    }
}
EOF
fi

# ------------------------------------------------------------
# Health check endpoint
# ------------------------------------------------------------
if [[ ! -f "api/healthz.php" ]]; then
  cat > api/healthz.php <<'EOF'
<?php
http_response_code(200);
echo json_encode([
  'status' => 'ok',
  'time' => time()
]);
EOF
fi

# ------------------------------------------------------------
# Dockerfile (PHP-FPM)
# ------------------------------------------------------------
if [[ ! -f "Dockerfile" ]]; then
  echo "🐳 Creating backend Dockerfile"
  cat > Dockerfile <<'EOF'
FROM php:8.3-fpm-alpine

RUN apk add --no-cache \
    bash \
    curl \
    icu-dev \
    oniguruma-dev \
    libzip-dev \
    mysql-client \
 && docker-php-ext-install \
    pdo \
    pdo_mysql \
    intl \
    zip

WORKDIR /var/www/html
COPY . .
RUN chown -R www-data:www-data /var/www/html

EXPOSE 9000
CMD ["php-fpm"]
EOF
fi

# ------------------------------------------------------------
# Basic DB schema
# ------------------------------------------------------------
if [[ ! -f "db/schema.sql" ]]; then
  cat > db/schema.sql <<'EOF'
CREATE TABLE users (
  id CHAR(36) PRIMARY KEY,
  email VARCHAR(255) UNIQUE,
  password_hash VARCHAR(255),
  role ENUM('player','admin','operator'),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE wallets (
  id CHAR(36) PRIMARY KEY,
  user_id CHAR(36),
  currency CHAR(3),
  balance DECIMAL(18,6),
  updated_at TIMESTAMP,
  INDEX(user_id)
);

CREATE TABLE ledger (
  id CHAR(36) PRIMARY KEY,
  wallet_id CHAR(36),
  amount DECIMAL(18,6),
  type VARCHAR(32),
  ref_id VARCHAR(64),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF
fi

# ------------------------------------------------------------
# Final check
# ------------------------------------------------------------
echo "✅ Backend core structure ready"
echo "[PHASE 10] BACKEND COMPLETE"
