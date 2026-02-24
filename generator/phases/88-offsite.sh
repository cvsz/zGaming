#!/usr/bin/env bash
set -euo pipefail

LATEST=$(ls -t backups/*.enc | head -1)

rclone copy "$LATEST" s3:casion-dr-bucket \
  --immutable \
  --checksum \
  --metadata-set dr=true

echo "✅ Offsite sync complete"