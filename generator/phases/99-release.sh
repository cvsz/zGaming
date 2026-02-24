#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 99] FINAL RELEASE – Package / Sign / Verify / Handover"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/release"
NAME="casino-platform"
VERSION="$(date +%Y.%m.%d-%H%M)"

mkdir -p "$OUT"/{artifacts,checksums,signatures,docs}

# ============================================================
# 1. Pre-flight validation (fail fast)
# ============================================================

echo "[CHECK] Required files"

req=(
  docker-compose.yml
  backend
  frontend-player
  frontend-admin
  nginx
  k8s
  generator/meta-master.sh
)

for r in "${req[@]}"; do
  [ -e "$ROOT/$r" ] || { echo "Missing $r"; exit 1; }
done

# ============================================================
# 2. Clean build (immutable artifacts)
# ============================================================

echo "[BUILD] Frontend production build"
docker compose build frontend-player frontend-admin

echo "[BUILD] Backend image"
docker compose build backend

# ============================================================
# 3. Export images (air-gap / regulator ready)
# ============================================================

echo "[EXPORT] Docker images"
IMAGES=(
  casino-platform-backend
  casino-platform-frontend-player
  casino-platform-frontend-admin
)

for img in "${IMAGES[@]}"; do
  docker save "$img" | gzip > "$OUT/artifacts/$img-$VERSION.tar.gz"
done

# ============================================================
# 4. Source code archive (exact state)
# ============================================================

echo "[ARCHIVE] Source code"
tar \
  --exclude=.git \
  --exclude=node_modules \
  --exclude=vendor \
  -czf "$OUT/artifacts/${NAME}-src-$VERSION.tar.gz" \
  docker-compose.yml \
  backend frontend-player frontend-admin nginx k8s generator

# ============================================================
# 5. Checksums (SHA256SUMS)
# ============================================================

echo "[CHECKSUM] SHA256"
(
  cd "$OUT/artifacts"
  sha256sum *.gz > "$OUT/checksums/SHA256SUMS"
)

# ============================================================
# 6. Cryptographic signing
# ============================================================

echo "[SIGN] Release signing"
if [ ! -f "$OUT/signatures/release.key" ]; then
  openssl genrsa -out "$OUT/signatures/release.key" 4096
  openssl rsa -in "$OUT/signatures/release.key" \
    -pubout -out "$OUT/signatures/release.pub"
fi

openssl dgst -sha256 \
  -sign "$OUT/signatures/release.key" \
  "$OUT/checksums/SHA256SUMS" \
  > "$OUT/signatures/SHA256SUMS.sig"

# ============================================================
# 7. Compliance documentation
# ============================================================

cat > "$OUT/docs/COMPLIANCE.md" <<EOF
# Compliance Summary

## Security
- JWT auth
- HMAC provider callbacks
- Idempotent wallet
- Rate limiting & WAF ready

## Audit
- auth_audit
- wallet ledger
- provider_callbacks

## Regulations
- KYC / AML hooks present
- Full transaction traceability
EOF

# ============================================================
# 8. Release manifest
# ============================================================

cat > "$OUT/RELEASE_MANIFEST.txt" <<EOF
Project: Casino Platform
Version: $VERSION

Artifacts:
- Docker images (gzipped)
- Full source archive
- SHA256SUMS
- Signed checksum

Verification:
openssl dgst -sha256 -verify release.pub \\
  -signature SHA256SUMS.sig SHA256SUMS
EOF

# ============================================================
# 9. Final ZIP (handover)
# ============================================================

echo "[PACKAGE] Final ZIP"
cd "$OUT"
zip -r "${NAME}-FINAL-$VERSION.zip" .

echo "✅ FINAL RELEASE READY"
echo "📦 Output: $OUT/${NAME}-FINAL-$VERSION.zip"