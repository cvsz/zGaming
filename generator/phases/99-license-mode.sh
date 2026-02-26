#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 99] LICENSE MODE"

LICENSE="${LICENSE:-MGA}"
CONF="config/license.json"
mkdir -p config

cat > "$CONF" <<EOF
{
  "license": "$LICENSE",
  "features": {
    "bonus": $( [[ "$LICENSE" == "UKGC" ]] && echo false || echo true ),
    "auto_withdraw": $( [[ "$LICENSE" == "PAGCOR" ]] && echo false || echo true ),
    "rg_mandatory": true
  }
}
EOF

echo "✅ License mode configured: $LICENSE"