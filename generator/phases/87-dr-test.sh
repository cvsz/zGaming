#!/usr/bin/env bash
set -euo pipefail

echo "[DR TEST]"

# simulate outage
docker stop casino-backend casino-nginx

sleep 5

# restore latest
LATEST=$(ls -t backups/*.enc | head -1)
./generator/phases/86-restore.sh "$LATEST"

docker compose up -d

curl -f http://localhost/api/healthz.php

echo "✅ DR TEST PASS"