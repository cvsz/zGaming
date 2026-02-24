#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 87] DISASTER RECOVERY TEST"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$ROOT/backups"

# --------------------------------------------------
# 0. Resolve latest backup
# --------------------------------------------------

LATEST_BACKUP="$(ls -1t "$BACKUP_DIR"/backup-*.tar.enc 2>/dev/null | head -n1 || true)"

[[ -n "$LATEST_BACKUP" && -f "$LATEST_BACKUP" ]] || {
  echo "❌ No backup found in $BACKUP_DIR"
  exit 1
}

echo "ℹ️ Using backup: $LATEST_BACKUP"

# --------------------------------------------------
# 1. Stop services (dynamic)
# --------------------------------------------------

echo "ℹ️ Simulating outage"

docker compose stop backend nginx || true

# Ensure DB stays up for restore
docker compose up -d db

# --------------------------------------------------
# 2. Restore from backup
# --------------------------------------------------

"$ROOT/generator/meta-master.sh" phase 86-restore.sh "$LATEST_BACKUP"

# --------------------------------------------------
# 3. Bring services back
# --------------------------------------------------

docker compose up -d backend nginx

# --------------------------------------------------
# 4. Wait for health
# --------------------------------------------------

echo "ℹ️ Waiting for service health"

for i in {1..30}; do
  if curl -fsS --max-time 2 http://localhost/api/healthz.php >/dev/null; then
    echo "✅ Health check passed"
    break
  fi
  sleep 2
done

curl -fsS http://localhost/api/healthz.php >/dev/null || {
  echo "❌ Health check failed after DR restore"
  exit 1
}

echo "✅ DR TEST PASS – restore successful"
