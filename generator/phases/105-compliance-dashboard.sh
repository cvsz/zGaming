#!/usr/bin/env bash
set -euo pipefail
echo "[PHASE 105] COMPLIANCE DASHBOARD"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/backend"
mkdir -p "$BACKEND/api/compliance"

cat > "$BACKEND/api/compliance/metrics.php" <<'PHP'
<?php
require_once __DIR__.'/../../core/Bootstrap.php';
Auth::requireRole('compliance');

echo json_encode([
  'wallet_ledger' => DB::one("SELECT COUNT(*) FROM wallet_ledger"),
  'risk_events'   => DB::one("SELECT COUNT(*) FROM risk_events"),
  'aml_flags'     => DB::one("SELECT COUNT(*) FROM wallet_ledger WHERE amount > 10000"),
  'rg_profiles'   => DB::one("SELECT COUNT(*) FROM rg_profile")
]);
PHP

echo "✅ Compliance dashboard endpoint ready"