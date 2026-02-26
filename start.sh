#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "=== zGaming START v3.5 (REPO-AWARE) ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR"

# --------------------------------------------------
# Resolve actual repo root
# --------------------------------------------------
if [[ -d "$BASE/zGaming/generator" ]]; then
  APP_DIR="$BASE/zGaming"
  MODE="nested-repo"
elif [[ -d "$BASE/generator" ]]; then
  APP_DIR="$BASE"
  MODE="repo-root"
elif [[ -d "$(pwd)/generator" ]]; then
  APP_DIR="$(pwd)"
  MODE="cwd"
else
  echo "❌ Cannot locate zGaming repository (generator missing)"
  exit 1
fi

echo "📂 Using application directory: $APP_DIR (mode: $MODE)"
cd "$APP_DIR"

# --------------------------------------------------
# Docker pre-flight
# --------------------------------------------------
for bin in docker curl openssl; do
  command -v "$bin" >/dev/null || { echo "❌ Required binary missing: $bin"; exit 1; }
done

docker info >/dev/null 2>&1 || {
  echo "❌ Docker permission denied"
  echo "👉 Add user to docker group or run with sudo"
  exit 1
}

# --------------------------------------------------
# Environment
# --------------------------------------------------
ENV_FILE="backend/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "🧩 Creating backend/.env"
  DB_PASS="casino_$(openssl rand -hex 4)"
  BACKUP_KEY="$(openssl rand -hex 32)"

  cat > "$ENV_FILE" <<EOF
APP_ENV=development
APP_DEBUG=true

DB_HOST=casino-db
DB_NAME=casino
DB_USER=casino
DB_PASS=$DB_PASS

BASE_CURRENCY=USD
BACKUP_KEY=$BACKUP_KEY
EOF
fi

# shellcheck disable=SC1090
source "$ENV_FILE"
export BACKUP_KEY DB_PASS

# --------------------------------------------------
# NGINX CONFIG (HARDENED)
# --------------------------------------------------
NGINX_DIR="$APP_DIR/nginx"
NGINX_CONF="$NGINX_DIR/nginx.conf"

echo "🛠 Ensuring nginx config"
mkdir -p "$NGINX_DIR"

if [[ -d "$NGINX_CONF" ]]; then
  echo "⚠ nginx.conf is a directory — fixing"
  rm -rf "$NGINX_CONF"
fi

if [[ ! -f "$NGINX_CONF" ]]; then
  cat > "$NGINX_CONF" <<'NGINX'
events {}
http {
  server {
    listen 80;
    location /api/healthz.php { return 200 "ok"; }
    location / { proxy_pass http://casino-backend:80; }
  }
}
NGINX
fi

# --------------------------------------------------
# Clean legacy containers
# --------------------------------------------------
echo "🧹 Cleaning legacy containers (if any)"
for c in casino-nginx casino-backend casino-db casino-frontend-player casino-frontend-admin; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    echo " - removing $c"
    docker rm -f "$c"
  fi
done

# --------------------------------------------------
# Docker Compose
# --------------------------------------------------
COMPOSE_FILE="$APP_DIR/docker-compose.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "❌ docker-compose.yml not found at $COMPOSE_FILE"
  exit 1
fi

echo "🐳 Starting containers"
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

# --------------------------------------------------
# Generator (dependency-safe)
# --------------------------------------------------
chmod +x generator/meta-master.sh

echo "⚙️ Pre-running required phases"
./generator/meta-master.sh phase 10-backend.sh
./generator/meta-master.sh phase 60-frontend.sh
./generator/meta-master.sh phase 70-nginx.sh

echo "🚀 Running full pipeline"
./generator/meta-master.sh all

# --------------------------------------------------
# Health check
# --------------------------------------------------
echo "🔍 Health check"
for i in {1..20}; do
  curl -fs http://localhost/api/healthz.php && break
  sleep 2
done

echo
echo "✅ zGaming STARTED SUCCESSFULLY"
echo "----------------------------------"
echo "🌐 App:  http://localhost"
echo "📂 Dir:  $APP_DIR"
echo "----------------------------------"
