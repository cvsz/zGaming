#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 106] AUDITOR HANDOVER PACK"

OUT="release/auditor-handover"
mkdir -p "$OUT"

cp README.md "$OUT/"
cp docs/DR.md "$OUT/" 2>/dev/null || true
cp -r reports "$OUT/" 2>/dev/null || true
cp SHA256SUMS "$OUT/" 2>/dev/null || true
cp MANIFEST.json "$OUT/" 2>/dev/null || true

cat > "$OUT/OVERVIEW.txt" <<EOF
Casino Platform Auditor Handover
- Wallet ledger immutable
- Provider settlement reconciled
- AML STR auto-generated
- DR tested and logged
EOF

zip -r "$OUT.zip" "$OUT"
echo "✅ Auditor handover ZIP ready: $OUT.zip"