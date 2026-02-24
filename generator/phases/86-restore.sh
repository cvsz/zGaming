#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="$1"
[ -f "$ARCHIVE" ] || { echo "Archive not found"; exit 1; }

ROOT="/opt/casino-platform"
TMP="/tmp/restore"

mkdir -p "$TMP"

# --------------------------------------------------
# 1. Decrypt
# --------------------------------------------------
openssl enc -d -aes-256-gcm \
  -pbkdf2 \
  -pass env:BACKUP_KEY \
  -in "$ARCHIVE" | tar xz -C "$TMP"

# --------------------------------------------------
# 2. Restore Config
# --------------------------------------------------
cp "$TMP/config/.env" "$ROOT/.env"

# --------------------------------------------------
# 3. Restore DB
# --------------------------------------------------
docker compose up -d db
sleep 10

docker exec -i casino-db \
  mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  < "$TMP/db/db.sql"

# --------------------------------------------------
# 4. Restore Secrets
# --------------------------------------------------
cp -r "$TMP/keys" "$ROOT/secrets"

echo "✅ Restore complete"