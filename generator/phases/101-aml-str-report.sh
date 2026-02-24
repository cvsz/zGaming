#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 101] AML STR AUTO-REPORT"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/reports/aml-str-$(date +%F)"
mkdir -p "$OUT"

THRESHOLD="${AML_THRESHOLD:-10000}"

docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "
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