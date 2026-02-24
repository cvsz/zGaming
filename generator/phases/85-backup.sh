#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 85] BACKUP"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="$ROOT/backups/$TS"

mkdir -p "$BACKUP"/{db,config,keys,meta}

# --------------------------------------------------
# ENV
# --------------------------------------------------
source "$ROOT/.env"

# --------------------------------------------------
# 1. Database (Consistent)
# --------------------------------------------------
docker exec casino-db \
  mysqldump \
  --single-transaction \
  --routines \
  --triggers \
  -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  > "$BACKUP/db/db.sql"

# --------------------------------------------------
# 2. Application Config
# --------------------------------------------------
cp "$ROOT/.env" "$BACKUP/config/.env"

# --------------------------------------------------
# 3. Secrets / Keys
# --------------------------------------------------
cp -r "$ROOT/secrets" "$BACKUP/keys" 2>/dev/null || true

# --------------------------------------------------
# 4. Metadata
# --------------------------------------------------
cat > "$BACKUP/meta/manifest.json" <<EOF
{
  "timestamp": "$TS",
  "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo unknown)",
  "services": ["backend","db","nginx"],
  "type": "full"
}
EOF

# --------------------------------------------------
# 5. Encrypt
# --------------------------------------------------
tar czf - -C "$BACKUP" . | \
  openssl enc -aes-256-gcm \
  -salt -pbkdf2 \
  -pass env:BACKUP_KEY \
  > "$BACKUP.tar.enc"

rm -rf "$BACKUP"

echo "✅ Backup complete: $BACKUP.tar.enc"