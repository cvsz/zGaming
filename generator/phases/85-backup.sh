#!/usr/bin/env bash
set -Eeuo pipefail

echo "[PHASE 85] BACKUP"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$ROOT/backups"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$BACKUP_DIR/backup-$TS"
DB_CONTAINER="casino-db"

mkdir -p "$BACKUP_DIR"

# --------------------------------------------------
# Load env
# --------------------------------------------------
ENV_FILE="$ROOT/backend/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ backend/.env missing"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"
export BACKUP_KEY DB_PASS

[[ -n "${BACKUP_KEY:-}" ]] || { echo "❌ BACKUP_KEY missing"; exit 1; }

# --------------------------------------------------
# Wait for MySQL
# --------------------------------------------------
echo "⏳ Waiting for MySQL in container $DB_CONTAINER"
for i in {1..30}; do
  if docker exec "$DB_CONTAINER" mysqladmin ping -u"$DB_USER" -p"$DB_PASS" --silent; then
    break
  fi
  sleep 2
done

# --------------------------------------------------
# Dump DB (container-safe)
# --------------------------------------------------
TMP="$(mktemp -d)"
mkdir -p "$TMP/db" "$TMP/config" "$TMP/meta"

echo "📦 Dumping database"
docker exec "$DB_CONTAINER" mysqldump \
  --single-transaction \
  --no-tablespaces \
  -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  > "$TMP/db/db.sql"

# --------------------------------------------------
# Config + metadata
# --------------------------------------------------
cp "$ENV_FILE" "$TMP/config/.env"

cat > "$TMP/meta/manifest.json" <<EOF
{
  "timestamp": "$TS",
  "type": "full",
  "db": "$DB_NAME"
}
EOF

# --------------------------------------------------
# Encrypt
# --------------------------------------------------
tar czf - -C "$TMP" . | \
  openssl enc -aes-256-cbc -pbkdf2 \
  -pass env:BACKUP_KEY \
  > "$OUT.tar.enc"

rm -rf "$TMP"

echo "✅ Backup complete: $OUT.tar.enc"
