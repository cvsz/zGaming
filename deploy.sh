#!/usr/bin/env bash
set -e

ACTIVE="$(cat .active 2>/dev/null || echo blue)"
NEXT=$([[ "$ACTIVE" == "blue" ]] && echo green || echo blue)

echo "▶ Deploying $NEXT"

docker compose -f docker-compose.$NEXT.yml up -d
sleep 10

curl -f http://localhost/api/healthz.php

docker compose -f docker-compose.$ACTIVE.yml down
echo "$NEXT" > .active

echo "✅ Switched to $NEXT"
