#!/usr/bin/env bash
set -Eeuo pipefail

echo "[PHASE 87] DISASTER RECOVERY TEST (FINAL)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$ROOT/backups"
COMPOSE="docker compose"

# --------------------------------------------------
# Resolve latest backup
# --------------------------------------------------
ARCHIVE="$(ls -t "$BACKUP_DIR"/backup-*.tar.enc 2>/dev/null | head -1 || true)"
[[ -f "$ARCHIVE" ]] || { echo "❌ No backup found"; exit 1; }

echo "ℹ️ Using backup: $ARCHIVE"

# --------------------------------------------------
# Stop everything
# --------------------------------------------------
echo "🛑 Stopping all containers"
$COMPOSE down

# --------------------------------------------------
# Start DB SERVICE ONLY (service name!)
# --------------------------------------------------
echo "▶️ Starting database service"
$COMPOSE up -d db

# --------------------------------------------------
# Restore database
# --------------------------------------------------
"$ROOT/generator/meta-master.sh" phase 86-restore.sh

# --------------------------------------------------
# Start remaining services
# --------------------------------------------------
echo "▶️ Starting all services"
$COMPOSE up -d

# --------------------------------------------------
# Health check
# --------------------------------------------------
echo "⏳ Waiting for backend health"
for i in {1..30}; do
  if curl -fs http://localhost/api/healthz.php >/dev/null; then
    echo "✅ DR TEST PASSED – Platform recovered"
    exit 0
  fi
  sleep 2
done

echo "❌ DR TEST FAILED – Backend did not recover"
exit 1
