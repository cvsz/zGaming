#!/usr/bin/env bash
set -Eeuo pipefail

echo "[PHASE 88] OFFSITE DR SYNC"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUPS="$ROOT/backups"

LATEST="$(ls -t "$BACKUPS"/backup-*.tar.enc | head -1)"

rclone copy "$LATEST" s3:casino-dr-bucket \
  --immutable \
  --checksum \
  --s3-storage-class GLACIER \
  --metadata-set dr=true

echo "✅ Offsite DR sync complete"
