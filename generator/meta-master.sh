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
PHASES_DIR="$ROOT/generator/phases"
LOG="$ROOT/meta-master.log"

exec > >(tee -a "$LOG") 2>&1

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
print_header() {
  echo "=================================================="
  echo " META-MASTER CASINO PLATFORM"
  echo " Root: $ROOT"
  echo "=================================================="
}

usage() {
  cat <<'USAGE'
Usage:
  ./generator/meta-master.sh all        # run full pipeline (default)
  ./generator/meta-master.sh final      # alias of `all`
  ./generator/meta-master.sh doctor     # run environment guard only
  ./generator/meta-master.sh phase <x>  # run one phase by filename
  ./generator/meta-master.sh list       # list phase execution order
USAGE
}

run_phase() {
  local phase="$1"

  if [[ ! -f "$PHASES_DIR/$phase" ]]; then
    echo "❌ Phase not found: $phase"
    exit 1
  fi

  echo
  echo ">>> RUNNING PHASE: $phase"
  echo "--------------------------------------------------"
  bash "$PHASES_DIR/$phase"
  echo "<<< DONE: $phase"
}

assert_layout() {
  if [[ ! -d "$PHASES_DIR" ]]; then
    echo "❌ PHASES directory not found:"
    echo "   $PHASES_DIR"
    exit 1
  fi
}

PHASE_ORDER=(
  "00-guard.sh"
  "10-backend.sh"
  "20-auth.sh"
  "30-wallet.sh"
  "35-fx.sh"
  "36-fx-live.sh"
  "37-currency-lock.sh"
  "38-multi-wallet.sh"
  "40-providers.sh"
  "50-callbacks.sh"
  "60-frontend.sh"
  "70-nginx.sh"
  "80-security.sh"
  "85-backup.sh"
  "86-restore.sh"
  "87-dr-test.sh"
  "88-offsite.sh"
  "90-cloudflare.sh"
  "91-hot-standby.sh"
  "92-regulator-report.sh"
  "93-settlement-engine.sh"
  "94-uat-checklist.sh"
  "95-k8s.sh"
  "96-bank-psp.sh"
  "97-responsible-gaming.sh"
  "98-risk-engine.sh"
  "99-license-mode.sh"
  "100-bank-reconciliation.sh"
  "101-aml-str-report.sh"
  "102-provider-certification.sh"
  "103-aml-str-xml.sh"
  "104-bank-settlement.sh"
  "105-compliance-dashboard.sh"
  "106-auditor-handover.sh"
  "110-runtest-report.sh"
  "99-release.sh"
)

run_all() {
  local phase
  for phase in "${PHASE_ORDER[@]}"; do
    run_phase "$phase"

    if [[ "$phase" == "00-guard.sh" ]]; then
      # load shared assertions after guard passes
      # shellcheck disable=SC1091
      source "$ROOT/generator/lib/assert.sh"
    fi
  done

  echo
  echo "=================================================="
  echo " 🎉 META-MASTER COMPLETE"
  echo "=================================================="
  echo " Logs   : $LOG"
  echo " Release: $ROOT/release/"
}

main() {
  local cmd="${1:-all}"

  print_header
  assert_layout

  case "$cmd" in
    all|final)
      run_all
      ;;
    doctor)
      run_phase "00-guard.sh"
      ;;
    phase)
      if [[ $# -lt 2 ]]; then
        echo "❌ Missing phase name"
        usage
        exit 1
      fi
      run_phase "$2"
      ;;
    list)
      printf '%s\n' "${PHASE_ORDER[@]}"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "❌ Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
