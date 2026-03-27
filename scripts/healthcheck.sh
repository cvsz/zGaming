#!/usr/bin/env bash
set -Eeuo pipefail

API_URL="${API_URL:-http://localhost:3000/health}"
TIMEOUT="${TIMEOUT:-5}"

if curl -fsS --max-time "$TIMEOUT" "$API_URL" >/dev/null; then
  echo "HEALTHCHECK_OK api=$API_URL"
else
  echo "HEALTHCHECK_FAIL api=$API_URL" >&2
  exit 1
fi
