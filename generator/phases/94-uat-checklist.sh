#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 94] REAL-MONEY UAT CHECKLIST"

CHECKS=(
 "Double callback idempotent"
 "Provider wallet isolation"
 "FX rate frozen per session"
 "Negative balance guard"
 "Failover standby read-only"
 "DR restore tested"
 "Settlement mismatch zero"
 "Regulator report generated"
 "KYC required before withdraw"
 "Rate limit enabled"
)

PASS=true

for c in "${CHECKS[@]}"; do
  echo "[ ] $c"
done

echo
echo ">>> Confirm all checks passed? (yes/no)"
read -r ans

if [[ "$ans" != "yes" ]]; then
  echo "❌ UAT FAILED – cannot go live"
  exit 1
fi

echo "✅ UAT PASSED – READY FOR REAL MONEY"