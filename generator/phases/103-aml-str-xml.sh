#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 103] AML STR XML (MGA / UKGC)"

DAY="${1:-$(date -d yesterday +%F)}"
LICENSE="${LICENSE:-MGA}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/reports/aml-str-xml-$DAY"
BACKEND_ENV="$ROOT/backend/.env"
mkdir -p "$OUT"

if [[ ! -f "$BACKEND_ENV" ]]; then
  echo "❌ Missing backend env file: $BACKEND_ENV"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$BACKEND_ENV"
set +a

DB_USER="${DB_USER:-casino}"
DB_PASS="${DB_PASS:-casino}"
DB_NAME="${DB_NAME:-casino}"
DB_CONTAINER="${DB_CONTAINER:-casino-db}"

for cmd in docker openssl zip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Required command not found: $cmd"
    exit 1
  fi
done

docker exec "$DB_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
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
  <Source>zGaming</Source>
</STRReport>
EOF

openssl dgst -sha256 "$OUT/str.xml" > "$OUT/str.xml.sig"
zip -r "$OUT.zip" "$OUT"
echo "✅ STR XML ready: $OUT.zip"
