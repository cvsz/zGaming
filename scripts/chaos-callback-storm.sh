#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_URL="${TARGET_URL:-http://localhost/api/provider/callback.php}"
IDEMPOTENCY_KEY="${IDEMPOTENCY_KEY:-chaos-storm-key-001}"
PARALLEL="${PARALLEL:-20}"
RETRIES="${RETRIES:-3}"

payload=$(cat <<EOF
{"provider":"chaos-test","event":"settlement","idempotencyKey":"$IDEMPOTENCY_KEY","amount":"1000","currency":"USDT"}
EOF
)

echo "[chaos] target=$TARGET_URL parallel=$PARALLEL retries=$RETRIES idempotency=$IDEMPOTENCY_KEY"

for round in $(seq 1 "$RETRIES"); do
  echo "[chaos] round=$round"
  seq 1 "$PARALLEL" | xargs -I{} -P "$PARALLEL" sh -c '
    code=$(curl -sS -o /tmp/zgaming-chaos-$$-{}.json -w "%{http_code}" \
      -H "Content-Type: application/json" \
      -d "$0" \
      "$1" || true)
    echo "request={} status=$code"
  ' "$payload" "$TARGET_URL"
done

echo "[chaos] complete. verify only 1 ledger row applied for key=$IDEMPOTENCY_KEY"
