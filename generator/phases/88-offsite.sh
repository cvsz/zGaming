// generator/phases/88-offsite.sh
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 88] OFFSITE BACKUP SYNC"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$ROOT/backups"

command -v rclone >/dev/null || { echo "❌ rclone missing"; exit 1; }
: "${OFFSITE_REMOTE:?missing OFFSITE_REMOTE}"

LATEST="$(ls -1t "$BACKUP_DIR"/backup-*.tar.enc 2>/dev/null | head -n1 || true)"
[[ -n "$LATEST" ]] || { echo "❌ No backup found"; exit 1; }

BASENAME="$(basename "$LATEST")"

rclone copyto "$LATEST" "$OFFSITE_REMOTE/$BASENAME" \
  --immutable \
  --checksum \
  --metadata-set dr=true

rclone ls "$OFFSITE_REMOTE" | grep -q "$BASENAME" || {
  echo "❌ Offsite verification failed"
  exit 1
}

echo "✅ Offsite sync complete"
