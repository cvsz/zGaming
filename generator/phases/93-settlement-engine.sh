#!/usr/bin/env bash
set -euo pipefail

PROVIDER="$1"
DATE="${2:-$(date -d yesterday +%F)}"

echo "[PHASE 93] SETTLEMENT $PROVIDER $DATE"

docker exec casino-db \
 mysql -u$DB_USER -p$DB_PASS $DB_NAME \
 -e "
INSERT INTO provider_settlement (provider,date,gross,net,currency,status)
SELECT
 provider,
 '$DATE',
 SUM(amount),
 SUM(amount),
 'USD',
 'open'
FROM wallet_ledger
WHERE provider='$PROVIDER'
  AND DATE(created_at)='$DATE'
GROUP BY provider
ON DUPLICATE KEY UPDATE
 gross=VALUES(gross),
 net=VALUES(net);
"

docker exec casino-db \
 mysql -u$DB_USER -p$DB_PASS $DB_NAME \
 -e "
SELECT
 s.provider,
 s.net settlement_net,
 SUM(l.amount) ledger_sum
FROM provider_settlement s
JOIN wallet_ledger l
  ON l.provider=s.provider
WHERE s.provider='$PROVIDER'
  AND s.date='$DATE'
GROUP BY s.provider
HAVING settlement_net != ledger_sum;
"

echo "✅ Settlement calculation complete"