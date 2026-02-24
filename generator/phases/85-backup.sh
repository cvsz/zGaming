#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 85] BACKUP"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
TMP_BACKUP="$(mktemp -d)"
FINAL_BACKUP="$ROOT/backups/backup-$TS.tar.enc"

mkdir -p "$ROOT/backups"

# --------------------------------------------------
# 0. Preconditions
# --------------------------------------------------

[[ -f "$ROOT/.env" ]] || {
  echo "❌ .env missing — cannot perform backup"
  exit 1
}

source "$ROOT/.env"

: "${DB_USER:?missing}"
: "${DB_PASS:?missing}"
: "${DB_NAME:?missing}"
: "${BACKUP_KEY:?missing BACKUP_KEY}"

# --------------------------------------------------
# 1. Resolve DB Container (dynamic)
# --------------------------------------------------

DB_CONTAINER="$(
  docker ps --format '{{.Names}}' | grep -E '(db|mysql)' | head -n1
)"

[[ -n "$DB_CONTAINER" ]] || {
  echo "❌ Database container not found"
  exit 1
}

echo "ℹ️ Using DB container: $DB_CONTAINER"

mkdir -p "$TMP_BACKUP"/{db,config,keys,meta}

# --------------------------------------------------
# 2. Database Backup (consistent)
# --------------------------------------------------

docker exec "$DB_CONTAINER" \
  mysqldump \
    --single-transaction \
    --routines \
    --triggers \
    -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  > "$TMP_BACKUP/db/db.sql"

# --------------------------------------------------
# 3. Application Config
# --------------------------------------------------

cp "$ROOT/.env" "$TMP_BACKUP/config/.env"

# --------------------------------------------------
# 4. Secrets (optional, safe)
# --------------------------------------------------

if [[ -d "$ROOT/secrets" ]]; then
  cp -r "$ROOT/secrets" "$TMP_BACKUP/keys"
fi

# --------------------------------------------------
# 5. Metadata
# --------------------------------------------------

cat > "$TMP_BACKUP/meta/manifest.json" <<EOF
{
  "timestamp": "$TS",
  "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo unknown)",
  "services": ["backend","db","nginx"],
  "type": "full"
}
EOF

# --------------------------------------------------
# 6. Encrypt (atomic)
# --------------------------------------------------

tar -C "$TMP_BACKUP" -czf - . | \
  openssl enc -aes-256-gcm \
    -salt -pbkdf2 \
    -pass env:BACKUP_KEY \
  > "$FINAL_BACKUP"

# --------------------------------------------------
# 7. Verify
# --------------------------------------------------

[[ -s "$FINAL_BACKUP" ]] || {
  echo "❌ Backup file is empty"
  exit 1
}

# --------------------------------------------------
# 8. Cleanup
# --------------------------------------------------

rm -rf "$TMP_BACKUP"

echo "✅ Backup complete: $FINAL_BACKUP"
