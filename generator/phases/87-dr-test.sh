// generator/phases/87-dr-test.sh
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 87] DISASTER RECOVERY TEST"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$ROOT/backups"

LATEST="$(ls -1t "$BACKUP_DIR"/backup-*.tar.enc 2>/dev/null | head -n1 || true)"
[[ -n "$LATEST" ]] || { echo "❌ No backup found"; exit 1; }

docker compose stop backend nginx || true
docker compose up -d db

"$ROOT/generator/meta-master.sh" phase 86-restore.sh "$LATEST"

docker compose up -d backend nginx

for i in {1..30}; do
  if curl -fs http://localhost/api/healthz.php >/dev/null; then
    echo "✅ Health check passed"
    exit 0
  fi
  sleep 2
done

echo "❌ DR test failed"
exit 1
