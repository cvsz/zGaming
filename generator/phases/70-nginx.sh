#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 70] NGINX – Reverse Proxy / Static / Security"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NGINX_DIR="$ROOT/nginx"

mkdir -p "$NGINX_DIR"

# ============================================================
# nginx.conf (single entry, prod-safe)
# ============================================================
cat > "$NGINX_DIR/nginx.conf" <<'NGINX'
worker_processes auto;
events { worker_connections 1024; }

http {
  include       mime.types;
  default_type  application/octet-stream;
  sendfile on;
  keepalive_timeout 65;

  # -------------------------
  # Logging
  # -------------------------
  log_format main '$remote_addr - $remote_user [$time_local] '
                  '"$request" $status $body_bytes_sent '
                  '"$http_referer" "$http_user_agent"';

  access_log /var/log/nginx/access.log main;
  error_log  /var/log/nginx/error.log warn;

  # -------------------------
  # Rate limit (API / callbacks)
  # -------------------------
  limit_req_zone $binary_remote_addr zone=api:10m rate=20r/s;

  # -------------------------
  # Security headers (OWASP baseline)
  # -------------------------
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;
  add_header Content-Security-Policy "
    default-src 'self';
    frame-src *;
    script-src 'self';
    style-src 'self' 'unsafe-inline';
    img-src * data:;
    connect-src *;
  " always;

  # ============================================================
  # SERVER
  # ============================================================
  server {
    listen 80;
    server_name _;

    # -------------------------
    # Player frontend
    # -------------------------
    location / {
      root /var/www/player;
      index index.html;
      try_files $uri $uri/ /index.html;
    }

    # -------------------------
    # Admin frontend
    # -------------------------
    location /admin/ {
      alias /var/www/admin/;
      index index.html;
      try_files $uri $uri/ /index.html;
    }

    # -------------------------
    # Backend API
    # -------------------------
    location /api/ {
      limit_req zone=api burst=40 nodelay;

      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;

      proxy_pass http://backend:9000/;
    }

    # -------------------------
    # Health check (LB / k8s)
    # -------------------------
    location /healthz {
      return 200 "ok";
    }
  }
}
NGINX

# ============================================================
# Docker notes (used by compose)
# ============================================================
cat > "$NGINX_DIR/README.md" <<'MD'
NGINX Reverse Proxy

- /            -> Player frontend (static)
- /admin       -> Admin frontend (static)
- /api         -> Backend PHP API (php-fpm)
- /healthz     -> Load balancer / k8s health

Cloudflare-ready (TLS terminated upstream).
MD

echo "✅ PHASE 70 COMPLETE – NGINX ready"