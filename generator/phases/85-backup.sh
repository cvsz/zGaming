#!/usr/bin/env bash
set -Eeuo pipefail

echo "[PHASE 85] BACKUP"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$ROOT/backups"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$BACKUP_DIR/backup-$TS"
DB_CONTAINER="casino-db"
DB_SERVICE="db"

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

for required_var in DB_USER DB_PASS DB_NAME; do
  [[ -n "${!required_var:-}" ]] || { echo "❌ $required_var missing in backend/.env"; exit 1; }
done

if [[ -z "${BACKUP_KEY:-}" ]]; then
  echo "⚠️ BACKUP_KEY missing in backend/.env; generating one"
  BACKUP_KEY="$(openssl rand -hex 32)"
  printf '\nBACKUP_KEY=%s\n' "$BACKUP_KEY" >> "$ENV_FILE"
  echo "✅ BACKUP_KEY generated and appended to backend/.env"
fi

export BACKUP_KEY DB_PASS

# --------------------------------------------------
# Docker prerequisite checks
# --------------------------------------------------
require_docker_ready() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker is required but not installed"
    echo "   Install docker + docker compose, then retry this phase."
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon is not reachable"
    echo "   Start Docker and verify \`docker info\` succeeds."
    exit 1
  fi
}

require_docker_ready

# --------------------------------------------------
# Ensure DB container exists/runs
# --------------------------------------------------
ensure_db_container() {
  if docker ps --format '{{.Names}}' | grep -Fxq "$DB_CONTAINER"; then
    echo "✅ MySQL container already running: $DB_CONTAINER"
    return 0
  fi

  if docker ps -a --format '{{.Names}}' | grep -Fxq "$DB_CONTAINER"; then
    echo "ℹ️ Starting existing MySQL container: $DB_CONTAINER"
    docker start "$DB_CONTAINER" >/dev/null
    return 0
  fi

  if [[ -f "$ROOT/docker-compose.yml" ]]; then
    echo "ℹ️ $DB_CONTAINER missing; attempting docker compose up -d $DB_SERVICE"
    local compose_out
    if ! compose_out="$(cd "$ROOT" && docker compose up -d "$DB_SERVICE" 2>&1)"; then
      echo "$compose_out"
      if grep -q "docker-credential-desktop\\.exe" <<<"$compose_out"; then
        echo "❌ Docker credential helper is misconfigured (docker-credential-desktop.exe not found)."
        echo "   Fix ~/.docker/config.json credsStore/credHelpers for this host, then retry."
      fi
      echo "❌ Failed to start $DB_SERVICE via docker compose."
      exit 1
    fi
    echo "$compose_out"
    return 0
  fi

  echo "❌ MySQL container $DB_CONTAINER is missing and docker-compose.yml was not found"
  exit 1
}

ensure_db_container

# --------------------------------------------------
# Wait for MySQL readiness
# --------------------------------------------------
echo "⏳ Waiting for MySQL in container $DB_CONTAINER"
MYSQL_READY=0
for i in {1..30}; do
  if docker exec "$DB_CONTAINER" mysqladmin ping -u"$DB_USER" -p"$DB_PASS" --silent; then
    MYSQL_READY=1
    break
  fi
  sleep 2
done

if [[ "$MYSQL_READY" -ne 1 ]]; then
  echo "❌ MySQL did not become ready in container $DB_CONTAINER"
  exit 1
fi

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
