#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail

echo "[PHASE 37] CURRENCY LOCK PER SESSION"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"

mkdir -p "$BACKEND"/{session,db,core}

# ============================================================
# 1. Session Currency Schema
# ============================================================

cat > "$BACKEND/db/session_currency.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS game_sessions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  provider VARCHAR(32) NOT NULL,
  game_code VARCHAR(64) NOT NULL,
  currency CHAR(3) NOT NULL,
  fx_rate DECIMAL(18,8) NOT NULL,
  status ENUM('active','closed') DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_active (user_id, provider, status)
);
SQL

# ============================================================
# 2. Currency Lock Domain Service
# ============================================================

cat > "$BACKEND/session/CurrencyLock.php" <<'PHP'
<?php
final class CurrencyLock {

  public static function create(
    int $userId,
    string $provider,
    string $gameCode,
    string $currency
  ): array {
    $db = Database::conn();

    $base = getenv('BASE_CURRENCY') ?: 'USD';
    $rate = FX::rate($currency, $base);

    $stmt = $db->prepare(
      "INSERT INTO game_sessions
       (user_id,provider,game_code,currency,fx_rate)
       VALUES (?,?,?,?,?)"
    );
    $stmt->execute([
      $userId,$provider,$gameCode,$currency,$rate
    ]);

    return [
      'session_id' => (int)$db->lastInsertId(),
      'currency'   => $currency,
      'fx_rate'    => $rate
    ];
  }

  public static function validate(
    int $userId,
    string $provider,
    string $currency
  ): array {
    $db = Database::conn();
    $stmt = $db->prepare(
      "SELECT * FROM game_sessions
       WHERE user_id=? AND provider=? AND status='active'
       ORDER BY created_at DESC LIMIT 1"
    );
    $stmt->execute([$userId,$provider]);
    $s = $stmt->fetch();

    if (!$s) {
      throw new RuntimeException("session_not_found");
    }

    if ($s['currency'] !== $currency) {
      throw new RuntimeException("currency_mismatch");
    }

    return $s;
  }

  public static function close(int $sessionId): void {
    Database::conn()->prepare(
      "UPDATE game_sessions SET status='closed' WHERE id=?"
    )->execute([$sessionId]);
  }
}
PHP

# ============================================================
# 3. Session Validator (Provider-Agnostic)
# ============================================================

cat > "$BACKEND/core/SessionValidator.php" <<'PHP'
<?php
final class SessionValidator {

  public static function enforce(
    int $userId,
    string $provider,
    string $currency
  ): array {
    return CurrencyLock::validate(
      $userId,$provider,$currency
    );
  }
}
PHP

# ============================================================
# 4. Documentation
# ============================================================

cat > "$BACKEND/session/README.md" <<'MD'
# Currency Lock per Session

## Rules
- Currency locked at game launch
- One active session per provider
- Callback currency must match
- FX snapshot stored at session creation

## Scope
- Provider-agnostic
- Provider launch & callbacks live in Phase 40+

## Why
- Prevent mid-game currency switch
- Prevent provider mismatch
- Audit-safe
MD

echo "✅ PHASE 37 COMPLETE – Currency locked per session (provider-agnostic)"
