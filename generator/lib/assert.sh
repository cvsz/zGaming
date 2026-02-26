#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'
	'

#!/usr/bin/env bash
# ============================================================
# ASSERT LIBRARY – META-MASTER
# DO NOT ASSUME GLOBAL PATHS
# ============================================================

set -euo pipefail

echo "=================================================="
echo "[ASSERT] CASINO PLATFORM PRE-FLIGHT CHECK"
echo "=================================================="

# ------------------------------------------------------------
# Resolve ROOT safely (from meta-master context)
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
fail () {
  echo "❌ ASSERT FAIL: $1"
  exit 1
}

ok () {
  echo "✅ $1"
}

# ------------------------------------------------------------
# [1] ENVIRONMENT FILES
# ------------------------------------------------------------
echo "[1] ENVIRONMENT"

# backend .env is REQUIRED
if [[ ! -f "$ROOT/backend/.env" ]]; then
  fail "backend/.env missing (run 10-backend.sh first)"
fi
ok "backend/.env present"

# global .env is OPTIONAL
if [[ -f "$ROOT/.env" ]]; then
  ok "root .env present (optional)"
else
  echo "ℹ️ root .env not present (optional, skipped)"
fi

# ------------------------------------------------------------
# [2] REQUIRED DIRECTORIES
# ------------------------------------------------------------
echo "[2] DIRECTORIES"

REQUIRED_DIRS=(
  "$ROOT/backend"
  "$ROOT/frontend-player"
  "$ROOT/frontend-admin"
  "$ROOT/nginx"
)

for d in "${REQUIRED_DIRS[@]}"; do
  [[ -d "$d" ]] || fail "missing directory $d"
  ok "directory exists: $d"
done

# ------------------------------------------------------------
# [3] DOCKERFILES
# ------------------------------------------------------------
echo "[3] DOCKERFILES"

REQUIRED_FILES=(
  "$ROOT/backend/Dockerfile"
)

for f in "${REQUIRED_FILES[@]}"; do
  [[ -f "$f" ]] || fail "missing file $f"
  ok "file exists: $f"
done

# ------------------------------------------------------------
# [4] HEALTH ENDPOINT
# ------------------------------------------------------------
echo "[4] HEALTHCHECK"

[[ -f "$ROOT/backend/api/healthz.php" ]] \
  || fail "backend health endpoint missing"

ok "health endpoint present"

echo "=================================================="
echo "[ASSERT] PRE-FLIGHT PASSED"
echo "=================================================="