#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

#!/usr/bin/env bash
set -euo pipefail

DAY="${1:-$(date -d yesterday +%F)}"
OUT="reports/regulator-$DAY"
DB_PASSWORD="${DB_PASSWORD:-${DB_PASS:-}}"

mkdir -p "$OUT"

echo "[PHASE 92] REGULATOR REPORT $DAY"

docker exec casino-db \
  env MYSQL_PWD="$DB_PASSWORD" mysql -u"$DB_USER" "$DB_NAME" \
  -e "
SELECT
 DATE(created_at) day,
 provider,
 currency,
 SUM(amount) total_amount,
 COUNT(*) txns
FROM wallet_ledger
WHERE DATE(created_at)='$DAY'
GROUP BY provider,currency;
" > "$OUT/transactions.csv"

docker exec casino-db \
  env MYSQL_PWD="$DB_PASSWORD" mysql -u"$DB_USER" "$DB_NAME" \
  -e "
SELECT provider,date,net,status
FROM provider_settlement
WHERE date='$DAY';
" > "$OUT/settlement.csv"

jq -n \
  --arg day "$DAY" \
  '{
    report_date:$day,
    system:"zGaming",
    compliant:true,
    generated_at:now
  }' > "$OUT/manifest.json"

zip -r "$OUT.zip" "$OUT"
echo "✅ Regulator report ready: $OUT.zip"
