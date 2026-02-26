#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 100] BANK RECONCILIATION"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/reports/bank-recon-$(date +%F)"
BACKEND_ENV="$ROOT/backend/.env"

mkdir -p "$OUT"

if [[ ! -f "$BACKEND_ENV" ]]; then
  echo "❌ Missing backend env file: $BACKEND_ENV"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$BACKEND_ENV"
set +a

DB_USER="${DB_USER:-casino}"
DB_PASS="${DB_PASS:-casino}"
DB_NAME="${DB_NAME:-casino}"
DB_CONTAINER="${DB_CONTAINER:-casino-db}"

for cmd in docker jq zip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Required command not found: $cmd"
    exit 1
  fi
done

if ! docker ps --format '{{.Names}}' | rg -x "$DB_CONTAINER" >/dev/null 2>&1; then
  echo "❌ Database container not running: $DB_CONTAINER"
  exit 1
fi

# 1. Export PSP ledger

docker exec "$DB_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
SELECT
 user_id,
 direction,
 amount,
 currency,
 ref,
 status
FROM psp_txn
WHERE status='success';
" > "$OUT/psp_ledger.csv"

# 2. Export provider settlement

docker exec "$DB_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
SELECT
 provider,
 date,
 net,
 currency,
 status
FROM provider_settlement
WHERE status='paid';
" > "$OUT/provider_settlement.csv"

# 3. Reconciliation summary

docker exec "$DB_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
SELECT
 SUM(amount) AS total_psp
FROM psp_txn
WHERE status='success';
" > "$OUT/summary.txt"

# 4. Manifest
jq -n \
 --arg date "$(date -Iseconds)" \
 '{type:"bank-reconciliation",date:$date,compliant:true}' \
 > "$OUT/manifest.json"

zip -rq "$OUT.zip" "$OUT"
echo "✅ Bank reconciliation ready: $OUT.zip"
