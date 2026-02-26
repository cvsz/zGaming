#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 96] BANK / PSP INTEGRATION"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/backend"
mkdir -p "$BACKEND/psp" "$BACKEND/db"

# DB
cat > "$BACKEND/db/psp.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS psp_txn (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  direction ENUM('deposit','withdraw') NOT NULL,
  amount DECIMAL(18,8) NOT NULL,
  currency CHAR(3) NOT NULL,
  ref VARCHAR(128) NOT NULL UNIQUE,
  status ENUM('pending','success','failed') NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQL

# PSP Adapter
cat > "$BACKEND/psp/PspAdapter.php" <<'PHP'
<?php
final class PspAdapter {
  public static function withdraw(int $userId, float $amount, string $currency, string $ref): array {
    // TODO: call bank/PSP API
    DB::exec("INSERT INTO psp_txn (user_id,direction,amount,currency,ref,status)
              VALUES (?,?,?,?,?,'pending')",
              [$userId,'withdraw',$amount,$currency,$ref]);
    return ['status'=>'pending','ref'=>$ref];
  }
}
PHP

echo "✅ PSP integration skeleton ready"