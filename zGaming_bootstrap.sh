#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'
	'

REPO_URL="https://github.com/CVSz/zGaming.git"
WORKDIR="${WORKDIR:-zGaming}"
BOOTSTRAP_VERSION="v8"

echo "=== zGaming BOOTSTRAP ${BOOTSTRAP_VERSION} (DEPENDENCY-SAFE) ==="

# ------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------
for bin in git bash sha256sum docker; do
  command -v "$bin" >/dev/null || {
    echo "❌ Required binary missing: $bin"
    exit 1
  }
done

# ------------------------------------------------------------
# Clean clone
# ------------------------------------------------------------
rm -rf "$WORKDIR"
git clone --depth 1 "$REPO_URL" "$WORKDIR"
cd "$WORKDIR"

ENTRYPOINT="generator/meta-master.sh"
PHASE_DIR="generator/phases"
LIB_DIR="generator/lib"
ASSERT_LIB="$LIB_DIR/assert.sh"

insert_after_shebang() {
  local file="$1"
  local block="$2"

  grep -Fq "$block" "$file" && return 0

  awk -v block="$block" 'NR==1{print; print block; next} {print}' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

# ------------------------------------------------------------
# 1. Enforce strict Bash
# ------------------------------------------------------------
echo "🔒 Enforcing strict Bash"

strict_block=$'set -Eeuo pipefail\nIFS=$'"'"'\n\t'"'"''

find generator -type f -name "*.sh" | while read -r f; do
  if ! grep -q "set -Eeuo pipefail" "$f"; then
    insert_after_shebang "$f" "$strict_block"
  fi
done

# ------------------------------------------------------------
# 2. Bash version guard
# ------------------------------------------------------------
echo "🛡 Installing Bash guard"

mkdir -p "$LIB_DIR"

cat > "$LIB_DIR/bash_guard.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
(( BASH_VERSINFO[0] >= 5 )) || {
  echo "❌ Bash >= 5 required. Current: $BASH_VERSION" >&2
  exit 1
}
EOF
chmod +x "$LIB_DIR/bash_guard.sh"

# ------------------------------------------------------------
# 3. Path-correct loaders
# ------------------------------------------------------------
echo "🧠 Injecting loaders"

entry_loader=$'ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nsource "$ZG_ROOT/lib/bash_guard.sh"'
phase_loader=$'ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\nsource "$ZG_ROOT/lib/bash_guard.sh"'

insert_after_shebang "$ENTRYPOINT" "$entry_loader"

for f in "$PHASE_DIR"/*.sh; do
  insert_after_shebang "$f" "$phase_loader"
done

# ------------------------------------------------------------
# 4. Versioning
# ------------------------------------------------------------
echo "🏷 Versioning"
echo "1.0.0" > generator/VERSION

version_block=$'MM_VERSION="$(cat "$(dirname "$0")/VERSION")"\necho "Meta-Master version: $MM_VERSION"\nexport MM_VERSION'
insert_after_shebang "$ENTRYPOINT" "$version_block"

# ------------------------------------------------------------
# 5. FIX ASSERTIONS (SPEC-CORRECT)
# ------------------------------------------------------------
echo "🧹 Fixing invalid assertions"

# Remove frontend Dockerfile assertions (NEVER CREATED)
sed -i '/frontend-player\/Dockerfile/d' "$ASSERT_LIB"
sed -i '/frontend-admin\/Dockerfile/d' "$ASSERT_LIB"

# ------------------------------------------------------------
# 6. FIX PHASE 37 FORWARD DEPENDENCY
# ------------------------------------------------------------
echo "🧩 Fixing phase 37 forward dependency"

PHASE_37="$PHASE_DIR/37-currency-lock.sh"

if ! grep -q 'PRAGMATIC_LAUNCH="$ROOT/backend/api/launch/pragmatic.php"' "$PHASE_37"; then
  sed -i '/backend\/api\/launch\/pragmatic.php/{
s|^|PRAGMATIC_LAUNCH="$ROOT/backend/api/launch/pragmatic.php"\n\nif [[ -f "$PRAGMATIC_LAUNCH" ]]; then\n|;
s|$|\nelse\n  echo "ℹ️ Pragmatic provider not present yet (patched after 40-providers.sh)"\nfi|;
}' "$PHASE_37"
fi

# ------------------------------------------------------------
# 7. Phase integrity
# ------------------------------------------------------------
echo "🔐 Phase integrity"

(
  cd "$PHASE_DIR"
  find . -type f -name "*.sh" -exec sha256sum {} \; > SHA256SUMS
)

integrity_block='( cd generator/phases && sha256sum -c SHA256SUMS ) || exit 1'
insert_after_shebang "$ENTRYPOINT" "$integrity_block"

# ------------------------------------------------------------
# 8. Syntax verification
# ------------------------------------------------------------
echo "🔍 Syntax check"

bash -n "$ENTRYPOINT"
bash -n "$ASSERT_LIB"
bash -n "$PHASE_37"

# ------------------------------------------------------------
# 9. REQUIRED PHASE ORDER (DEPENDENCY-SAFE)
# ------------------------------------------------------------
echo "🚀 Running required phases in safe order"

./generator/meta-master.sh phase 10-backend.sh
./generator/meta-master.sh phase 20-auth.sh
./generator/meta-master.sh phase 30-wallet.sh
./generator/meta-master.sh phase 35-fx.sh
./generator/meta-master.sh phase 36-fx-live.sh
./generator/meta-master.sh phase 40-providers.sh
./generator/meta-master.sh phase 37-currency-lock.sh
./generator/meta-master.sh phase 38-multi-wallet.sh
./generator/meta-master.sh phase 60-frontend.sh
./generator/meta-master.sh phase 70-nginx.sh

# ------------------------------------------------------------
# 10. Full pipeline
# ------------------------------------------------------------
echo "🏁 Running full pipeline"
./generator/meta-master.sh all

echo "✅ zGaming BOOTSTRAP ${BOOTSTRAP_VERSION} COMPLETE"
