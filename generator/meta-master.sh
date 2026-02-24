#!/usr/bin/env bash
# ============================================================
# META-MASTER CASINO PLATFORM
# FINAL / PRODUCTION / REGULATOR-GRADE
# ============================================================

set -euo pipefail

# ------------------------------------------------------------
# Resolve absolute paths (RUN FROM ANYWHERE)
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PHASES="$ROOT/generator/phases"
LOG="$ROOT/meta-master.log"

exec > >(tee -a "$LOG") 2>&1

echo "=================================================="
echo " META-MASTER CASINO PLATFORM"
echo " Root: $ROOT"
echo "=================================================="

# ------------------------------------------------------------
# Hard Path Assert (Fail-fast)
# ------------------------------------------------------------
if [[ ! -d "$PHASES" ]]; then
  echo "❌ PHASES directory not found:"
  echo "   $PHASES"
  exit 1
fi

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
run_phase () {
  local phase="$1"

  if [[ ! -f "$PHASES/$phase" ]]; then
    echo "❌ Phase not found: $phase"
    exit 1
  fi

  echo
  echo ">>> RUNNING PHASE: $phase"
  echo "--------------------------------------------------"
  bash "$PHASES/$phase"
  echo "<<< DONE: $phase"
}

# ------------------------------------------------------------
# PHASE EXECUTION ORDER (SOURCE OF TRUTH)
# ------------------------------------------------------------

# 00 — Guards / Assert
run_phase "00-guard.sh"

# load shared assertions (library, not phase)
source "$ROOT/generator/lib/assert.sh"

# 10 — Core Backend / DB
run_phase "10-backend.sh"

# 20 — Auth / JWT / Role
run_phase "20-auth.sh"

# 30 — Wallet Core
run_phase "30-wallet.sh"

# 35–38 — FX / Currency / Multi-Wallet
run_phase "35-fx.sh"
run_phase "36-fx-live.sh"
run_phase "37-currency-lock.sh"
run_phase "38-multi-wallet.sh"

# 40 — Game Providers
run_phase "40-providers.sh"

# 50 — Provider Callbacks / Idempotency
run_phase "50-callbacks.sh"

# 60 — Frontend (Player / Admin)
run_phase "60-frontend.sh"

# 70 — NGINX / Reverse Proxy
run_phase "70-nginx.sh"

# 80 — Security Hardening (OWASP)
run_phase "80-security.sh"

# 85–88 — Backup / DR / Restore / Offsite
run_phase "85-backup.sh"
run_phase "86-restore.sh"
run_phase "87-dr-test.sh"
run_phase "88-offsite.sh"

# 90 — Cloudflare / HTTPS
run_phase "90-cloudflare.sh"

# 91 — Hot-Standby Multi-Region
run_phase "91-hot-standby.sh"

# 92 — Regulator Report
run_phase "92-regulator-report.sh"

# 93 — Provider Settlement Engine
run_phase "93-settlement-engine.sh"

# 94 — Real-Money UAT Gate
run_phase "94-uat-checklist.sh"

# 95 — Kubernetes (Helm / Kustomize)
run_phase "95-k8s.sh"

# 96–99 — Finance / Compliance / License
run_phase "96-bank-psp.sh"
run_phase "97-responsible-gaming.sh"
run_phase "98-risk-engine.sh"
run_phase "99-license-mode.sh"

# 100–102 — Finance / AML / Provider Cert
run_phase "100-bank-reconciliation.sh"
run_phase "101-aml-str-report.sh"
run_phase "102-provider-certification.sh"

# 103–106 — STR XML / Settlement / Compliance / Auditor
run_phase "103-aml-str-xml.sh"
run_phase "104-bank-settlement.sh"
run_phase "105-compliance-dashboard.sh"
run_phase "106-auditor-handover.sh"

# 110 — Final Go-Live Test & Report
run_phase "110-runtest-report.sh"

# 99 — FINAL RELEASE (ZIP / CHECKSUM / SIGN)
run_phase "99-release.sh"

# ------------------------------------------------------------
# DONE
# ------------------------------------------------------------
echo
echo "=================================================="
echo " 🎉 META-MASTER COMPLETE"
echo "=================================================="
echo " Logs   : $LOG"
echo " Release: $ROOT/release/"