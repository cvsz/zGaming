#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 97] RESPONSIBLE GAMING"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/backend"
mkdir -p "$BACKEND/rg" "$BACKEND/db"

cat > "$BACKEND/db/responsible_gaming.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS rg_profile (
  user_id BIGINT PRIMARY KEY,
  daily_limit DECIMAL(18,8),
  monthly_limit DECIMAL(18,8),
  self_excluded_until DATETIME
);
SQL

cat > "$BACKEND/rg/ResponsibleGaming.php" <<'PHP'
<?php
final class ResponsibleGaming {
  public static function assertAllowed(int $userId, float $amount): void {
    $rg = DB::one("SELECT * FROM rg_profile WHERE user_id=?",[$userId]);
    if (!$rg) return;

    if ($rg['self_excluded_until'] && strtotime($rg['self_excluded_until']) > time()) {
      throw new Exception("SELF_EXCLUDED");
    }
  }
}
PHP

echo "✅ Responsible gaming enforced"