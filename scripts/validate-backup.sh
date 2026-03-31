#!/usr/bin/env bash
set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "Usage: $0 <backup.sql.gz>" >&2
  exit 1
fi

sha256sum -c "$FILE.sha256"
gzip -t "$FILE"
zcat "$FILE" | head -n 5 >/dev/null

echo "backup_valid=$FILE"
