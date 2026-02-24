#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 88] OFFSITE BACKUP SYNC"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$ROOT/backups"

# --------------------------------------------------
# 0. Preconditions
# --------------------------------------------------

command -v rclone >/dev/null 2>&1 || {
  echo "❌ rclone not installed"
  exit 1
}

: "${OFFSITE_REMOTE:?missing OFFSITE_REMOTE (e.g. s3:casino-dr-bucket)}"

# --------------------------------------------------
# 1. Resolve latest backup
# --------------------------------------------------

LATEST_BACKUP="$(ls -1t "$BACKUP_DIR"/backup-*.tar.enc 2>/dev/null | head -n1 || true)"

[[ -n "$LATEST_BACKUP" && -f "$LATEST_BACKUP" ]] || {
  echo "❌ No backup found in $BACKUP_DIR"
  exit 1
}

BASENAME="$(basename "$LATEST_BACKUP")"
REMOTE_PATH="$OFFSITE_REMOTE/$BASENAME"

echo "ℹ️ Using backup: $LATEST_BACKUP"
echo "ℹ️ Offsite target: $REMOTE_PATH"

# --------------------------------------------------
# 2. Upload (immutable, checksum verified)
# --------------------------------------------------

rclone copyto \
  "$LATEST_BACKUP" \
  "$REMOTE_PATH" \
  --immutable \
  --checksum \
  --metadata-set dr=true \
  --stats-one-line \
  --stats 10s

# --------------------------------------------------
# 3. Verify presence
# --------------------------------------------------

rclone ls "$OFFSITE_REMOTE" | grep -q "$BASENAME" || {
  echo "❌ Offsite verification failed"
  exit 1
}

echo "✅ Offsite sync complete: $REMOTE_PATH"
