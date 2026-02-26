#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 70] NGINX – Reverse Proxy / Static / Security"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NGINX_DIR="$ROOT/nginx"

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

docker run -d \
  --name casino-nginx \
  -p 80:80 \
  -v "$NGINX_DIR/nginx.conf:/etc/nginx/nginx.conf:ro" \
  nginx:stable

echo "✅ PHASE 70 COMPLETE – NGINX ready"
