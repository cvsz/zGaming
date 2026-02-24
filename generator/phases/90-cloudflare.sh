#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 90] CLOUDFLARE – HTTPS / Tunnel / Zero Trust"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CF="$ROOT/cloudflare"
NGINX="$ROOT/nginx"

mkdir -p "$CF"/{tunnel,docs}

# ============================================================
# 1. cloudflared config (Tunnel mode – recommended)
# ============================================================

cat > "$CF/tunnel/config.yml" <<'YAML'
tunnel: casino-platform
credentials-file: /etc/cloudflared/creds.json

ingress:
  - hostname: casino.example.com
    service: http://nginx:80
  - hostname: admin.casino.example.com
    service: http://nginx:80
  - service: http_status:404
YAML

# ============================================================
# 2. Docker Compose snippet (cloudflared)
# ============================================================

cat > "$CF/tunnel/docker-compose.cloudflared.yml" <<'YAML'
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: casino-cloudflared
    command: tunnel run casino-platform
    volumes:
      - ./cloudflare/tunnel:/etc/cloudflared
    restart: unless-stopped
    networks:
      - default
YAML

# ============================================================
# 3. Zero Trust headers (NGINX trust CF only)
# ============================================================

cat > "$CF/nginx-cloudflare.conf" <<'NGINX'
# Trust Cloudflare IPs only
real_ip_header CF-Connecting-IP;

set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 131.0.72.0/22;
NGINX

# Inject into nginx.conf if not present
if ! grep -q CF-Connecting-IP "$NGINX/nginx.conf"; then
  sed -i '/http {/a \ \ include /etc/nginx/cloudflare.conf;' "$NGINX/nginx.conf"
fi

# ============================================================
# 4. HTTPS expectations (TLS at Cloudflare)
# ============================================================

cat > "$CF/docs/HTTPS.md" <<'MD'
# HTTPS Model

TLS is terminated at Cloudflare edge.

NGINX listens on port 80 only.
Origin is NOT publicly exposed.

Benefits:
- Automatic cert rotation
- DDoS protection
- WAF
- Zero Trust Access
MD

# ============================================================
# 5. WAF rules recommendation (doc)
# ============================================================

cat > "$CF/docs/WAF.md" <<'MD'
# Cloudflare WAF Rules (Recommended)

- Block non-Cloudflare traffic to origin
- Rate limit /api/callback (5 r/s)
- Block countries not in business scope
- Bot Fight Mode: ON
- Challenge suspicious IP reputation

This complements NGINX WAF-lite.
MD

# ============================================================
# 6. Health check (Cloudflare LB / Tunnel)
# ============================================================

cat > "$CF/docs/HEALTH.md" <<'MD'
Health Endpoint:
- GET /healthz

Used by:
- Cloudflare Load Balancer
- Tunnel monitoring
- Kubernetes probes
MD

# ============================================================
# 7. Fail-fast guard for prod
# ============================================================

cat > "$CF/cloudflare-check.sh" <<'BASH'
#!/usr/bin/env bash
set -e

[[ -f /etc/cloudflared/creds.json ]] || exit 1
[[ -f /etc/cloudflared/config.yml ]] || exit 1
BASH

chmod +x "$CF/cloudflare-check.sh"

echo "✅ PHASE 90 COMPLETE – Cloudflare edge ready"