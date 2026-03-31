#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 102] PROVIDER CERTIFICATION CHECKLIST"

CHECKLIST=(
 "Launch URL signature verified"
 "Callback IP whitelisted"
 "Callback idempotency enforced"
 "Wallet debit/credit exact"
 "Rollback supported"
 "Negative balance impossible"
 "Latency tolerance tested"
 "Double callback tested"
 "Provider settlement matches ledger"
 "DR test evidence available"
 "UAT real-money passed"
)

OUT="reports/provider-certification-$(date +%F)"
mkdir -p "$OUT"

printf "Provider Certification Checklist\n\n" > "$OUT/checklist.txt"

PASS=true
for c in "${CHECKLIST[@]}"; do
  printf "[ ] %s\n" "$c" >> "$OUT/checklist.txt"
done

if [[ "${MM_NONINTERACTIVE:-0}" == "1" ]]; then
  echo "⚠ MM_NONINTERACTIVE=1 -> auto-confirming provider certification checklist"
  ans="yes"
else
  printf "\nConfirm all items passed? (yes/no): "
  read -r ans
fi

if [[ "$ans" != "yes" ]]; then
  echo "❌ Certification FAILED"
  exit 1
fi

jq -n \
 '{provider_certified:true, date:now}' \
 > "$OUT/manifest.json"

zip -r "$OUT.zip" "$OUT"
echo "✅ Provider certification package ready"
