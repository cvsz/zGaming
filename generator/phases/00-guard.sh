#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 00] GUARD – Environment & Safety Checks"

# --------------------------------------------------
# Resolve ROOT from meta-master context
# --------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --------------------------------------------------
# Shell
# --------------------------------------------------
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "❌ GUARD FAILED: Must run with bash"
  exit 1
fi
echo "✅ Shell is bash"

# --------------------------------------------------
# Docker
# --------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "❌ GUARD FAILED: docker not installed"
  exit 1
fi
echo "✅ docker available"

# --------------------------------------------------
# Docker Compose (v2 preferred)
# --------------------------------------------------
if docker compose version >/dev/null 2>&1; then
  export COMPOSE_CMD="docker compose"
  echo "✅ docker compose v2 detected"
elif command -v docker-compose >/dev/null 2>&1; then
  export COMPOSE_CMD="docker-compose"
  echo "⚠ docker-compose v1 detected (deprecated)"
else
  echo "❌ GUARD FAILED: docker compose not available"
  exit 1
fi

# --------------------------------------------------
# Docker permission
# --------------------------------------------------
if ! docker ps >/dev/null 2>&1; then
  echo "❌ GUARD FAILED: docker permission denied"
  echo "   Fix: sudo usermod -aG docker $USER && logout"
  exit 1
fi
echo "✅ docker permission OK"

# --------------------------------------------------
# Directory structure
# --------------------------------------------------
if [[ ! -d "$ROOT/generator" ]]; then
  echo "❌ GUARD FAILED: missing directory $ROOT/generator"
  exit 1
fi

echo "✅ repository structure OK"

# Optional strict mode for pre-provisioned deployments.
# Set MM_GUARD_STRICT_LAYOUT=1 to enforce that generated directories already exist.
if [[ "${MM_GUARD_STRICT_LAYOUT:-0}" == "1" ]]; then
  REQUIRED_DIRS=(
    "backend"
    "frontend-player"
    "frontend-admin"
    "nginx"
  )

  for d in "${REQUIRED_DIRS[@]}"; do
    if [[ ! -d "$ROOT/$d" ]]; then
      echo "❌ GUARD FAILED (strict): missing directory $ROOT/$d"
      exit 1
    fi
  done

  echo "✅ strict directory layout OK"
fi

echo "[PHASE 00] GUARD PASSED"
