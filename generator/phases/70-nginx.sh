#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 70] NGINX – Reverse Proxy / Static / Security"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NGINX_DIR="$ROOT/nginx"

require_docker_ready() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker CLI not found. Install Docker before running phase 70."
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon is not reachable. Start Docker and retry phase 70."
    exit 1
  fi
}

warn_linux_desktop_credsstore() {
  local config_file="${HOME}/.docker/config.json"
  local uname_s

  uname_s="$(uname -s)"
  if [[ "$uname_s" != "Linux" ]]; then
    return 0
  fi

  if [[ -f "$config_file" ]] && grep -Eq '"cred[sS]tore"[[:space:]]*:[[:space:]]*"desktop"' "$config_file"; then
    cat <<'MSG'
❌ Docker config uses `"credsStore": "desktop"` on Linux.
   This points to docker-credential-desktop.exe (Windows/macOS helper) and breaks image pulls.
   Fix: remove the credsStore entry from ~/.docker/config.json, then retry this phase.
MSG
    exit 1
  fi
}

require_docker_ready
warn_linux_desktop_credsstore

mkdir -p "$NGINX_DIR"

cat > "$NGINX_DIR/nginx.conf" <<'CONF'
events {}
http {
  server {
    listen 80;
    location /api/healthz.php {
      return 200 "ok";
    }
  }
}
CONF

docker rm -f casino-nginx 2>/dev/null || true

docker pull nginx:stable >/dev/null

docker run -d \
  --name casino-nginx \
  -p 80:80 \
  -v "$NGINX_DIR/nginx.conf:/etc/nginx/nginx.conf:ro" \
  nginx:stable

echo "✅ PHASE 70 COMPLETE – NGINX ready"
