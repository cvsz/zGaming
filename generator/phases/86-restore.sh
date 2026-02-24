#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 86] RESTORE"

# --------------------------------------------------
# Resolve ROOT correctly (generator-safe)
# --------------------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$ROOT/backups"
TMP_RESTORE="$(mktemp -d)"

# --------------------------------------------------
# 0. Resolve backup archive (arg or latest)
# --------------------------------------------------

if [[ -n "${1:-}" ]]; then
  ARCHIVE="$1"
else
  ARCHIVE="$(ls -1t "$BACKUP_DIR"/backup-*.tar.enc 2>/dev/null | head -n1 || true)"
fi

[[ -n "$ARCHIVE" && -f "$ARCHIVE" ]] || {
  echo "❌ Backup archive not found"
  exit 1
}

echo "ℹ️ Using archive: $ARCHIVE"

# --------------------------------------------------
# 1. Resolve ENV (backend preferred)
# --------------------------------------------------

ENV_FILE=""
if [[ -f "$ROOT/backend/.env" ]]; then
  ENV_FILE="$ROOT/backend/.env"
elif [[ -f "$ROOT/.env" ]]; then
  ENV_FILE="$ROOT/.env"
else
  echo "❌ No .env found (expected backend/.env or root .env)"
  exit 1
fi

echo "ℹ️ Using env file: $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${DB_USER:?missing}"
: "${DB_PASS:?missing}"
: "${DB_NAME:?missing}"

# --------------------------------------------------
# Resolve BACKUP_KEY (env > file > prompt)
# --------------------------------------------------

if [[ -n "${BACKUP_KEY:-}" ]]; then
  :
elif [[ -n "${BACKUP_KEY_FILE:-}" && -f "$BACKUP_KEY_FILE" ]]; then
  BACKUP_KEY="$(<"$BACKUP_KEY_FILE")"
  export BACKUP_KEY
elif [[ -t 0 ]]; then
  read -rsp "Enter BACKUP_KEY: " BACKUP_KEY
  echo
  export BACKUP_KEY
else
  echo "❌ BACKUP_KEY not provided"
  exit 1
fi

[[ -n "$BACKUP_KEY" ]] || {
  echo "❌ BACKUP_KEY empty"
  exit 1
}

# --------------------------------------------------
# 2. Decrypt & Extract (matches Phase 85 exactly)
# --------------------------------------------------

openssl enc -d -aes-256-cbc \
  -pbkdf2 -iter 100000 \
  -pass env:BACKUP_KEY \
  -in "$ARCHIVE" | \
  tar -C "$TMP_RESTORE" -xzf -

# --------------------------------------------------
# 3. Resolve DB container dynamically
# --------------------------------------------------

DB_CONTAINER="$(
  docker ps --format '{{.Names}}' | grep -E '(db|mysql)' | head -n1
)"

[[ -n "$DB_CONTAINER" ]] || {
  echo "❌ Database container not found"
  exit 1
}

echo "ℹ️ Using DB container: $DB_CONTAINER"

# --------------------------------------------------
# 4. Restore Database
# --------------------------------------------------

[[ -f "$TMP_RESTORE/db/db.sql" ]] || {
  echo "❌ db.sql missing in backup"
  exit 1
}

docker exec -i "$DB_CONTAINER" \
  mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  < "$TMP_RESTORE/db/db.sql"

# --------------------------------------------------
# 5. Restore Config (non-destructive)
# --------------------------------------------------

if [[ -f "$TMP_RESTORE/config/.env" ]]; then
  cp "$TMP_RESTORE/config/.env" "$ENV_FILE"
fi

# --------------------------------------------------
# 6. Restore Secrets (optional)
# --------------------------------------------------

if [[ -d "$TMP_RESTORE/keys" ]]; then
  mkdir -p "$ROOT/secrets"
  cp -r "$TMP_RESTORE/keys/"* "$ROOT/secrets/"
fi

# --------------------------------------------------
# 7. Cleanup
# --------------------------------------------------

rm -rf "$TMP_RESTORE"

echo "✅ Restore complete from $ARCHIVE"
