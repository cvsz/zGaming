#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 101] AML STR AUTO-REPORT"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/reports/aml-str-$(date +%F)"
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

THRESHOLD="${AML_THRESHOLD:-10000}"

docker exec "$DB_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
SELECT
 user_id,
 provider,
 SUM(amount) total_amount,
 COUNT(*) txns
FROM wallet_ledger
WHERE DATE(created_at)=CURDATE()
GROUP BY user_id,provider
HAVING total_amount > $THRESHOLD;
" > "$OUT/suspicious.csv"

jq -n \
 --arg threshold "$THRESHOLD" \
 '{
   report_type:"AML_STR",
   threshold:$threshold,
   generated_at:now
 }' > "$OUT/manifest.json"

zip -r "$OUT.zip" "$OUT"
echo "⚠ AML STR report generated: $OUT.zip"
