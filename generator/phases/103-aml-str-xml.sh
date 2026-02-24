#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 103] AML STR XML (MGA / UKGC)"

DAY="${1:-$(date -d yesterday +%F)}"
LICENSE="${LICENSE:-MGA}"
OUT="reports/aml-str-xml-$DAY"
mkdir -p "$OUT"

docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "
SELECT user_id, provider, SUM(amount) total_amount
FROM wallet_ledger
WHERE DATE(created_at)='$DAY'
GROUP BY user_id, provider
HAVING total_amount > ${AML_THRESHOLD:-10000};
" > "$OUT/str.csv"

cat > "$OUT/str.xml" <<EOF
<STRReport license="$LICENSE" date="$DAY">
  <GeneratedAt>$(date -Is)</GeneratedAt>
  <Threshold>${AML_THRESHOLD:-10000}</Threshold>
  <Source>casino-platform</Source>
</STRReport>
EOF

openssl dgst -sha256 "$OUT/str.xml" > "$OUT/str.xml.sig"
zip -r "$OUT.zip" "$OUT"
echo "✅ STR XML ready: $OUT.zip"