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
OUT="reports/bank-settlement-$DATE"
mkdir -p "$OUT"

docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "
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