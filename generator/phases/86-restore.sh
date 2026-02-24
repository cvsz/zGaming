// generator/phases/86-restore.sh
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 86] RESTORE"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$ROOT/backups"
TMP_RESTORE="$(mktemp -d)"

ARCHIVE="${1:-$(ls -1t "$BACKUP_DIR"/backup-*.tar.enc 2>/dev/null | head -n1 || true)}"
[[ -n "$ARCHIVE" && -f "$ARCHIVE" ]] || { echo "❌ Backup archive not found"; exit 1; }

echo "ℹ️ Using archive: $ARCHIVE"

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

if [[ -z "${BACKUP_KEY:-}" ]]; then
  read -rsp "Enter BACKUP_KEY: " BACKUP_KEY; echo
  export BACKUP_KEY
fi

openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
  -pass env:BACKUP_KEY \
  -in "$ARCHIVE" | tar -C "$TMP_RESTORE" -xzf -

DB_CONTAINER="$(docker ps --format '{{.Names}}' | grep -E '(db|mysql)' | head -n1)"
[[ -n "$DB_CONTAINER" ]] || { echo "❌ DB container not found"; exit 1; }

docker exec -i "$DB_CONTAINER" \
  mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  < "$TMP_RESTORE/db/db.sql"

[[ -f "$TMP_RESTORE/config/.env" ]] && cp "$TMP_RESTORE/config/.env" "$ENV_FILE"

if compgen -G "$TMP_RESTORE/keys/*" > /dev/null; then
  mkdir -p "$ROOT/secrets"
  cp -r "$TMP_RESTORE/keys/"* "$ROOT/secrets/"
fi

rm -rf "$TMP_RESTORE"
echo "✅ Restore complete from $ARCHIVE"
