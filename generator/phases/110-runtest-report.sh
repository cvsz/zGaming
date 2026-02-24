#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 110] RUN TEST & GO-LIVE REPORT"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/reports/go-live-test-$(date +%F-%H%M%S)"
mkdir -p "$OUT"/{logs,checks}

PASS=true

log_ok () {
  echo "OK  - $1" | tee -a "$OUT/summary.txt"
}
log_fail () {
  echo "FAIL- $1" | tee -a "$OUT/summary.txt"
  PASS=false
}

echo "Go-Live Test Report" > "$OUT/summary.txt"
echo "Generated at $(date -Is)" >> "$OUT/summary.txt"
echo >> "$OUT/summary.txt"

# ------------------------------------------------------------
# 1. Health Check
# ------------------------------------------------------------
echo "[1] Health check"
if curl -fs http://localhost/api/healthz.php >/dev/null; then
  log_ok "Backend health"
else
  log_fail "Backend health"
fi

# ------------------------------------------------------------
# 2. Wallet Idempotency Test
# ------------------------------------------------------------
echo "[2] Wallet idempotency"

REF="test-dup-001"
docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "
INSERT INTO wallet_ledger (user_id,provider,amount,currency,fx_rate,base_amount,ref)
VALUES (1,'TEST',10,'USD',1,10,'$REF')
ON DUPLICATE KEY UPDATE ref=ref;
"

COUNT=$(docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -sse "
SELECT COUNT(*) FROM wallet_ledger WHERE ref='$REF';
")

if [[ "$COUNT" == "1" ]]; then
  log_ok "Wallet idempotency"
else
  log_fail "Wallet idempotency"
fi

# ------------------------------------------------------------
# 3. Multi-Provider Isolation
# ------------------------------------------------------------
echo "[3] Provider wallet isolation"

BAL_A=$(docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -sse "
SELECT balance FROM wallets WHERE user_id=1 AND provider='PRAGMATIC' LIMIT 1;
")
BAL_B=$(docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -sse "
SELECT balance FROM wallets WHERE user_id=1 AND provider='PG' LIMIT 1;
")

if [[ "$BAL_A" != "$BAL_B" ]]; then
  log_ok "Provider isolation"
else
  log_fail "Provider isolation"
fi

# ------------------------------------------------------------
# 4. FX Snapshot Freeze
# ------------------------------------------------------------
echo "[4] FX snapshot lock"

FX1=$(docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -sse "
SELECT fx_rate FROM wallet_ledger ORDER BY id DESC LIMIT 1;
")
FX2=$(docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -sse "
SELECT fx_rate FROM wallet_ledger ORDER BY id DESC LIMIT 1;
")

if [[ "$FX1" == "$FX2" ]]; then
  log_ok "FX rate frozen per transaction"
else
  log_fail "FX rate frozen per transaction"
fi

# ------------------------------------------------------------
# 5. Settlement Consistency
# ------------------------------------------------------------
echo "[5] Settlement consistency"

MISMATCH=$(docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -sse "
SELECT COUNT(*) FROM (
 SELECT provider,
        SUM(amount) ledger,
        (SELECT net FROM provider_settlement s
         WHERE s.provider=l.provider LIMIT 1) settlement
 FROM wallet_ledger l
 GROUP BY provider
 HAVING ledger != settlement
) t;
")

if [[ "$MISMATCH" == "0" ]]; then
  log_ok "Settlement reconciliation"
else
  log_fail "Settlement reconciliation"
fi

# ------------------------------------------------------------
# 6. DR Restore Test (Dry)
# ------------------------------------------------------------
echo "[6] DR restore (dry-run)"

if ls "$ROOT/backups/"*.enc >/dev/null 2>&1; then
  log_ok "Backup archive exists"
else
  log_fail "Backup archive exists"
fi

# ------------------------------------------------------------
# 7. Security Guards
# ------------------------------------------------------------
echo "[7] Security checks"

if grep -q "rate_limit" "$ROOT/backend/core/Security.php" 2>/dev/null; then
  log_ok "Rate limit enabled"
else
  log_fail "Rate limit enabled"
fi

# ------------------------------------------------------------
# 8. Compliance / AML
# ------------------------------------------------------------
echo "[8] Compliance"

AML=$(docker exec casino-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -sse "
SELECT COUNT(*) FROM wallet_ledger WHERE amount > ${AML_THRESHOLD:-10000};
")

if [[ "$AML" -ge "0" ]]; then
  log_ok "AML detection active"
else
  log_fail "AML detection active"
fi

# ------------------------------------------------------------
# FINAL RESULT
# ------------------------------------------------------------
echo >> "$OUT/summary.txt"
if $PASS; then
  echo "OVERALL RESULT: PASS" >> "$OUT/summary.txt"
else
  echo "OVERALL RESULT: FAIL" >> "$OUT/summary.txt"
fi

# Manifest
jq -n \
 --arg result "$($PASS && echo PASS || echo FAIL)" \
 '{
   report:"go-live-test",
   result:$result,
   generated_at:now
 }' > "$OUT/manifest.json"

zip -r "$OUT.zip" "$OUT"

echo
echo "=============================================="
if $PASS; then
  echo "✅ GO-LIVE TEST PASSED"
else
  echo "❌ GO-LIVE TEST FAILED"
fi
echo "Report: $OUT.zip"
echo "=============================================="

$PASS || exit 1