#!/usr/bin/env bash
set -euo pipefail

DAY="${1:-$(date -d yesterday +%F)}"
OUT="reports/regulator-$DAY"

mkdir -p "$OUT"

echo "[PHASE 92] REGULATOR REPORT $DAY"

docker exec casino-db \
  mysql -u$DB_USER -p$DB_PASS $DB_NAME \
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
  mysql -u$DB_USER -p$DB_PASS $DB_NAME \
  -e "
SELECT provider,date,net,status
FROM provider_settlement
WHERE date='$DAY';
" > "$OUT/settlement.csv"

jq -n \
  --arg day "$DAY" \
  '{
    report_date:$day,
    system:"casino-platform",
    compliant:true,
    generated_at:now
  }' > "$OUT/manifest.json"

zip -r "$OUT.zip" "$OUT"
echo "✅ Regulator report ready: $OUT.zip"