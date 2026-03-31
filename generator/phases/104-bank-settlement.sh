#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 104] BANK SETTLEMENT AUTOMATION"

DATE="${1:-$(date -d yesterday +%F)}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/reports/bank-settlement-$DATE"
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
DB_PASSWORD="${DB_PASSWORD:-${DB_PASS:-casino}}"
DB_NAME="${DB_NAME:-casino}"
DB_CONTAINER="${DB_CONTAINER:-casino-db}"

for cmd in docker zip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Required command not found: $cmd"
    exit 1
  fi
done

docker exec "$DB_CONTAINER" env MYSQL_PWD="$DB_PASSWORD" mysql -u"$DB_USER" "$DB_NAME" -e "
SELECT provider, SUM(net) net_amount
FROM provider_settlement
WHERE date='$DATE' AND status='open'
GROUP BY provider;
" > "$OUT/net.csv"

cat > "$OUT/payment.json" <<EOF
{
  "date": "$DATE",
  "currency": "USD",
  "instructions": "Execute bank transfer per provider net"
}
EOF

zip -r "$OUT.zip" "$OUT"
echo "✅ Bank settlement package ready: $OUT.zip"
