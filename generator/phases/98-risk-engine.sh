#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 98] RISK ENGINE"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/backend"
mkdir -p "$BACKEND/risk" "$BACKEND/db"

cat > "$BACKEND/db/risk.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS risk_events (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT,
  type VARCHAR(32),
  score INT,
  meta JSON,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQL

cat > "$BACKEND/risk/RiskEngine.php" <<'PHP'
<?php
final class RiskEngine {
  public static function score(int $userId, string $type, array $meta): void {
    $score = 0;
    if ($type === 'velocity') $score = 30;
    if ($type === 'collusion') $score = 80;

    DB::exec("INSERT INTO risk_events (user_id,type,score,meta)
              VALUES (?,?,?,?)",
              [$userId,$type,$score,json_encode($meta)]);
  }
}
PHP

echo "✅ Risk engine active"