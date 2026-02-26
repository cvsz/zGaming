#!/usr/bin/env bash
MM_VERSION="$(cat "$(dirname "$0")/VERSION")"
echo "Meta-Master version: $MM_VERSION"
export MM_VERSION

ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

# ============================================================
# META-MASTER CASINO PLATFORM
# FINAL / PRODUCTION / REGULATOR-GRADE
# ============================================================

set -Eeuo pipefail

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
  ./generator/meta-master.sh all                    # run full pipeline (default)
  ./generator/meta-master.sh final                  # alias of `all`
  ./generator/meta-master.sh installer              # alias of `all`
  ./generator/meta-master.sh upgrade                # re-run full pipeline safely
  ./generator/meta-master.sh test                   # run go-live test/report phase
  ./generator/meta-master.sh doctor                 # run environment guard only
  ./generator/meta-master.sh phase <file>           # run one phase by filename
  ./generator/meta-master.sh list                   # list phase execution order
  ./generator/meta-master.sh status                 # validate phase catalog and layout

Optional environment variables:
  MM_FROM_PHASE=<phase-file>    # start from this phase (all/final/installer/upgrade)
  MM_TO_PHASE=<phase-file>      # stop at this phase (all/final/installer/upgrade)
USAGE
}

fail() {
  echo "❌ $1"
  exit 1
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

assert_layout() {
  [[ -d "$PHASES_DIR" ]] || fail "PHASES directory not found: $PHASES_DIR"
}

validate_phase_catalog() {
  local phase seen=""
  local -i missing_count=0

  for phase in "${PHASE_ORDER[@]}"; do
    if [[ ",${seen}," == *",${phase},"* ]]; then
      fail "Duplicate phase entry in PHASE_ORDER: $phase"
    fi
    seen+="${phase},"

    if [[ ! -f "$PHASES_DIR/$phase" ]]; then
      echo "❌ Missing phase file: $PHASES_DIR/$phase"
      missing_count+=1
    fi
  done

  if (( missing_count > 0 )); then
    fail "Phase catalog validation failed (${missing_count} missing files)"
  fi

  echo "✅ Phase catalog validated (${#PHASE_ORDER[@]} phases)"
}

phase_index() {
  local target="$1"
  local i
  for i in "${!PHASE_ORDER[@]}"; do
    if [[ "${PHASE_ORDER[$i]}" == "$target" ]]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

run_phase() {
  local phase="$1"

  [[ -f "$PHASES_DIR/$phase" ]] || fail "Phase not found: $phase"

  echo
  echo ">>> RUNNING PHASE: $phase"
  echo "--------------------------------------------------"
  bash "$PHASES_DIR/$phase"
  echo "<<< DONE: $phase"
}

print_summary() {
  local total="$1"
  local succeeded="$2"
  local started_at="$3"
  local finished_at

  finished_at="$(date +%s)"

  echo
  echo "=================================================="
  echo " EXECUTION SUMMARY"
  echo "--------------------------------------------------"
  echo " Total phases planned : $total"
  echo " Total phases success : $succeeded"
  echo " Total phases failed  : $((total - succeeded))"
  echo " Duration (seconds)   : $((finished_at - started_at))"
  echo "=================================================="
}

run_all() {
  local from_phase="${MM_FROM_PHASE:-${1:-}}"
  local to_phase="${MM_TO_PHASE:-${2:-}}"
  local from_index=0
  local to_index=$(( ${#PHASE_ORDER[@]} - 1 ))
  local i phase started_at total planned=0 succeeded=0

  if [[ -n "$from_phase" ]]; then
    from_index="$(phase_index "$from_phase")" || fail "MM_FROM_PHASE not found in PHASE_ORDER: $from_phase"
  fi

  if [[ -n "$to_phase" ]]; then
    to_index="$(phase_index "$to_phase")" || fail "MM_TO_PHASE not found in PHASE_ORDER: $to_phase"
  fi

  if (( from_index > to_index )); then
    fail "Invalid range: MM_FROM_PHASE must be before MM_TO_PHASE"
  fi

  started_at="$(date +%s)"

  for i in "${!PHASE_ORDER[@]}"; do
    if (( i < from_index || i > to_index )); then
      continue
    fi
    planned+=1
  done

  total="$planned"

  for i in "${!PHASE_ORDER[@]}"; do
    if (( i < from_index || i > to_index )); then
      continue
    fi

    phase="${PHASE_ORDER[$i]}"
    run_phase "$phase"
    succeeded=$((succeeded + 1))

    if [[ "$phase" == "00-guard.sh" ]]; then
      # load shared assertions after guard passes
      # shellcheck disable=SC1091
      source "$ROOT/generator/lib/assert.sh"
    fi
  done

  print_summary "$total" "$succeeded" "$started_at"

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
  validate_phase_catalog

  case "$cmd" in
    all|final|installer|install)
      run_all
      ;;
    upgrade)
      export MM_UPGRADE_MODE=1
      echo "🔄 UPGRADE MODE ENABLED"
      run_all
      ;;
    test)
      run_phase "00-guard.sh"
      run_phase "110-runtest-report.sh"
      ;;
    doctor)
      run_phase "00-guard.sh"
      ;;
    phase)
      if [[ $# -lt 2 ]]; then
        fail "Missing phase name"
      fi
      run_phase "$2"
      ;;
    list)
      printf '%s\n' "${PHASE_ORDER[@]}"
      ;;
    status)
      echo "✅ Status OK"
      echo "   Root      : $ROOT"
      echo "   Phases dir: $PHASES_DIR"
      echo "   Log file  : $LOG"
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
