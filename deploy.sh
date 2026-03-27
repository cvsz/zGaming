#!/usr/bin/env bash
set -Eeuo pipefail

ACTIVE="$(cat .active 2>/dev/null || echo blue)"
NEXT=$([[ "$ACTIVE" == "blue" ]] && echo green || echo blue)
HEALTH_URL="${HEALTH_URL:-http://localhost/api/healthz.php}"
HEALTH_RETRIES="${HEALTH_RETRIES:-20}"
HEALTH_SLEEP_SECONDS="${HEALTH_SLEEP_SECONDS:-3}"

echo "▶ Deploying $NEXT"

if [[ ! -f "docker-compose.$NEXT.yml" ]]; then
  echo "❌ Missing compose file: docker-compose.$NEXT.yml" >&2
  exit 1
fi

if [[ ! -f "docker-compose.$ACTIVE.yml" ]]; then
  echo "❌ Missing compose file: docker-compose.$ACTIVE.yml" >&2
  exit 1
fi

docker compose -f docker-compose.$NEXT.yml up -d
sleep 5

for ((i = 1; i <= HEALTH_RETRIES; i++)); do
  if curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null; then
    echo "✅ Health check passed: $HEALTH_URL"
    break
  fi

  if [[ "$i" -eq "$HEALTH_RETRIES" ]]; then
    echo "❌ Health check failed after $HEALTH_RETRIES attempts: $HEALTH_URL" >&2
    exit 1
  fi

  echo "⏳ Health check retry $i/$HEALTH_RETRIES..."
  sleep "$HEALTH_SLEEP_SECONDS"
done

docker compose -f docker-compose.$ACTIVE.yml down
echo "$NEXT" > .active

echo "✅ Switched to $NEXT"
