#!/usr/bin/env bash
set -Eeuo pipefail

API_URL="${1:-${API_URL:-http://localhost:3000/health}}"
TIMEOUT="${TIMEOUT:-5}"
TRACE_URL="${TRACE_URL:-http://localhost:4318/v1/traces}"

if curl -fsS --max-time "$TIMEOUT" "$API_URL" >/dev/null; then
  echo "HEALTHCHECK_OK api=$API_URL"
else
  echo "HEALTHCHECK_FAIL api=$API_URL" >&2
  exit 1
fi

if curl -sS --max-time "$TIMEOUT" -o /dev/null -w "%{http_code}" "$TRACE_URL" | rg -q '^(200|400|401|404|405)$'; then
  echo "TRACE_ENDPOINT_REACHABLE url=$TRACE_URL"
else
  echo "TRACE_ENDPOINT_UNREACHABLE url=$TRACE_URL" >&2
fi
