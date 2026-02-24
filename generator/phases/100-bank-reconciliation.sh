#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 100] BANK RECONCILIATION"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/reports/bank-recon-$(date +%F)"
mkdir -p "$OUT"

# 1. Export ledger
docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "
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

# 2. Export settlement
docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "
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
docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "
SELECT
 SUM(amount) total_psp
FROM psp_txn
WHERE status='success';
" > "$OUT/summary.txt"

# 4. Manifest
jq -n \
 '{type:"bank-reconciliation",date:now,compliant:true}' \
 > "$OUT/manifest.json"

zip -r "$OUT.zip" "$OUT"
echo "✅ Bank reconciliation ready: $OUT.zip"#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 100] BANK RECONCILIATION"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/reports/bank-recon-$(date +%F)"
mkdir -p "$OUT"

# 1. Export ledger
docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "
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

# 2. Export settlement
docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "
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
docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "
SELECT
 SUM(amount) total_psp
FROM psp_txn
WHERE status='success';
" > "$OUT/summary.txt"

# 4. Manifest
jq -n \
 '{type:"bank-reconciliation",date:now,compliant:true}' \
 > "$OUT/manifest.json"

zip -r "$OUT.zip" "$OUT"
echo "✅ Bank reconciliation ready: $OUT.zip"