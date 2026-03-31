#!/usr/bin/env bash
set -Eeuo pipefail

echo "[PHASE 86] RESTORE"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$ROOT/backups"
DB_CONTAINER="casino-db"

# --------------------------------------------------
# Resolve archive
# --------------------------------------------------
ARCHIVE="${1:-}"
if [[ -z "$ARCHIVE" ]]; then
  ARCHIVE="$(ls -t "$BACKUP_DIR"/backup-*.tar.enc 2>/dev/null | head -1 || true)"
fi

[[ -f "$ARCHIVE" ]] || { echo "❌ Backup archive not found"; exit 1; }

echo "ℹ️ Using archive: $ARCHIVE"

# --------------------------------------------------
# Load env
# --------------------------------------------------
ENV_FILE="$ROOT/backend/.env"
[[ -f "$ENV_FILE" ]] || { echo "❌ backend/.env missing"; exit 1; }

# shellcheck disable=SC1090
source "$ENV_FILE"
DB_PASSWORD="${DB_PASSWORD:-${DB_PASS:-}}"
export BACKUP_KEY DB_PASSWORD

[[ -n "${BACKUP_KEY:-}" ]] || { echo "❌ BACKUP_KEY missing"; exit 1; }

# --------------------------------------------------
# Temp dir
# --------------------------------------------------
TMP="$(mktemp -d)"

# --------------------------------------------------
# Decrypt + extract (MATCH PHASE 85)
# --------------------------------------------------
openssl enc -d -aes-256-cbc -pbkdf2 \
  -pass env:BACKUP_KEY \
  -in "$ARCHIVE" | tar xz -C "$TMP"

# --------------------------------------------------
# Restore config
# --------------------------------------------------
cp "$TMP/config/.env" "$ENV_FILE"

# --------------------------------------------------
# Wait for MySQL
# --------------------------------------------------
echo "⏳ Waiting for MySQL"
for i in {1..30}; do
  if docker exec "$DB_CONTAINER" env MYSQL_PWD="$DB_PASSWORD" mysqladmin ping -u"$DB_USER" --silent; then
    break
  fi
  sleep 2
done

# --------------------------------------------------
# Restore DB
# --------------------------------------------------
docker exec -i "$DB_CONTAINER" \
  env MYSQL_PWD="$DB_PASSWORD" mysql -u"$DB_USER" "$DB_NAME" \
  < "$TMP/db/db.sql"

rm -rf "$TMP"

echo "✅ Restore complete from $ARCHIVE"
