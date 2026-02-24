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
# 0. Resolve ENV (backend preferred)
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
  export BACKUP_KEY
elif [[ -n "${BACKUP_KEY_FILE:-}" && -f "$BACKUP_KEY_FILE" ]]; then
  BACKUP_KEY="$(<"$BACKUP_KEY_FILE")"
  export BACKUP_KEY
elif [[ -t 0 ]]; then
  read -rsp "Enter BACKUP_KEY: " BACKUP_KEY
  echo
  export BACKUP_KEY
else
  echo "❌ BACKUP_KEY not provided (env, file, or prompt)"
  exit 1
fi

[[ -n "$BACKUP_KEY" ]] || {
  echo "❌ BACKUP_KEY empty"
  exit 1
}

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
# 2. Database Backup (least-privilege safe)
# --------------------------------------------------

docker exec "$DB_CONTAINER" \
  mysqldump \
    --single-transaction \
    --routines \
    --triggers \
    --no-tablespaces \
    -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  > "$TMP_BACKUP/db/db.sql"

# --------------------------------------------------
# 3. Application Config
# --------------------------------------------------

cp "$ENV_FILE" "$TMP_BACKUP/config/.env"

# --------------------------------------------------
# 4. Secrets (optional)
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
# 6. Encrypt (portable & strong)
# --------------------------------------------------

tar -C "$TMP_BACKUP" -czf - . | \
  openssl enc -aes-256-cbc \
    -salt -pbkdf2 -iter 100000 \
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
