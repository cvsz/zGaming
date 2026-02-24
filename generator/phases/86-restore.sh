// generator/phases/85-backup.sh
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 85] BACKUP"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
TMP_BACKUP="$(mktemp -d)"
FINAL_BACKUP="$ROOT/backups/backup-$TS.tar.enc"

mkdir -p "$ROOT/backups"

# Resolve ENV (backend preferred)
if [[ -f "$ROOT/backend/.env" ]]; then
  ENV_FILE="$ROOT/backend/.env"
elif [[ -f "$ROOT/.env" ]]; then
  ENV_FILE="$ROOT/.env"
else
  echo "❌ No .env found"
  exit 1
fi

echo "ℹ️ Using env file: $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${DB_USER:?missing}"
: "${DB_PASS:?missing}"
: "${DB_NAME:?missing}"

# Resolve BACKUP_KEY (env > file > prompt)
if [[ -n "${BACKUP_KEY:-}" ]]; then
  :
elif [[ -n "${BACKUP_KEY_FILE:-}" && -f "$BACKUP_KEY_FILE" ]]; then
  BACKUP_KEY="$(<"$BACKUP_KEY_FILE")"
  export BACKUP_KEY
elif [[ -t 0 ]]; then
  read -rsp "Enter BACKUP_KEY: " BACKUP_KEY; echo
  export BACKUP_KEY
else
  echo "❌ BACKUP_KEY not provided"
  exit 1
fi

# Resolve DB container
DB_CONTAINER="$(docker ps --format '{{.Names}}' | grep -E '(db|mysql)' | head -n1)"
[[ -n "$DB_CONTAINER" ]] || { echo "❌ DB container not found"; exit 1; }

mkdir -p "$TMP_BACKUP"/{db,config,keys,meta}

docker exec "$DB_CONTAINER" \
  mysqldump \
    --single-transaction \
    --routines \
    --triggers \
    --no-tablespaces \
    -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  > "$TMP_BACKUP/db/db.sql"

cp "$ENV_FILE" "$TMP_BACKUP/config/.env"
[[ -d "$ROOT/secrets" ]] && cp -r "$ROOT/secrets" "$TMP_BACKUP/keys"

cat > "$TMP_BACKUP/meta/manifest.json" <<EOF
{
  "timestamp": "$TS",
  "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo unknown)",
  "type": "full"
}
EOF

tar -C "$TMP_BACKUP" -czf - . | \
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
  -pass env:BACKUP_KEY \
  > "$FINAL_BACKUP"

[[ -s "$FINAL_BACKUP" ]] || { echo "❌ Backup empty"; exit 1; }

rm -rf "$TMP_BACKUP"
echo "✅ Backup complete: $FINAL_BACKUP"
