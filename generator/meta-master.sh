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
STATE_DIR="${MM_STATE_DIR:-$ROOT/.meta-master-state}"
mkdir -p "$STATE_DIR"
ENV_FILE="$ROOT/.env"

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
  ./generator/meta-master.sh clean-installer [mode] # run ultra clean installer (quick/full/diagnostics/audit)
  ./generator/meta-master.sh upgrade                # re-run full pipeline safely
  ./generator/meta-master.sh test                   # run go-live test/report phase
  ./generator/meta-master.sh doctor                 # run environment guard only
  ./generator/meta-master.sh phase <file>           # run one phase by filename
  ./generator/meta-master.sh list                   # list phase execution order
  ./generator/meta-master.sh status                 # validate phase catalog and layout
  ./generator/meta-master.sh scan                   # full logic scan + upgrade plan artifact

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
  "107-meta-orchestrator.sh"
  "108-release.sh"
  "109-institutional-finance.sh"
  "110-runtest-report.sh"
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

validate_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    cat > "$ENV_FILE" <<'EOF'
MYSQL_ROOT_PASSWORD=
DB_NAME=
DB_USER=
DB_PASSWORD=
EOF
    fail "Created $ENV_FILE template. Fill required values and re-run."
  fi

  set -o allexport
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +o allexport

  export DB_PASS="${DB_PASS:-${DB_PASSWORD:-}}"
  export DB_PASSWORD="${DB_PASSWORD:-${DB_PASS:-}}"

  local -a required_vars=("MYSQL_ROOT_PASSWORD" "DB_NAME" "DB_USER" "DB_PASSWORD")
  local var

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      fail "Missing required env var: $var"
    fi
  done

  echo "✅ Environment validation passed (DB_USER=$DB_USER DB_NAME=$DB_NAME)"
}

phase_hash() {
  local phase="$1"
  sha256sum "$PHASES_DIR/$phase" | awk '{print $1}'
}

run_phase_safe() {
  local phase="$1"
  local phase_file="$PHASES_DIR/$phase"

  [[ -f "$phase_file" ]] || fail "Phase not found: $phase"

  echo
  echo ">>> RUNNING PHASE: $phase"
  echo "--------------------------------------------------"

  if ! bash "$phase_file"; then
    fail "PHASE FAILED: $phase"
  fi

  echo "<<< DONE: $phase"
}

wait_for_docker_healthy() {
  local service="$1"
  local timeout_seconds="${2:-120}"
  local elapsed=0
  local cid health

  cid="$(docker compose -f "$ROOT/docker-compose.yml" ps -q "$service" 2>/dev/null || true)"
  [[ -n "$cid" ]] || return 0

  while (( elapsed < timeout_seconds )); do
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || true)"
    if [[ "$health" == "healthy" || "$health" == "none" ]]; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  fail "Docker service '$service' did not become healthy in ${timeout_seconds}s"
}

wait_for_mysql_ready() {
  local service="${1:-db}"
  local timeout_seconds="${2:-120}"
  local elapsed=0

  while (( elapsed < timeout_seconds )); do
    if docker compose -f "$ROOT/docker-compose.yml" exec -T \
      -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$service" \
      mysqladmin ping -uroot --silent >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  fail "MySQL readiness check failed after ${timeout_seconds}s"
}

init_mysql_if_needed() {
  if [[ "${MM_SKIP_DOCKER_ACTIONS:-0}" == "1" ]]; then
    echo "⚠ MM_SKIP_DOCKER_ACTIONS=1 -> skipping MySQL bootstrap"
    return 0
  fi

  docker compose -f "$ROOT/docker-compose.yml" up -d db >/dev/null
  wait_for_docker_healthy "db"
  wait_for_mysql_ready "db"

  docker compose -f "$ROOT/docker-compose.yml" exec -T \
    -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" db \
    mysql -uroot -e "
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
ALTER USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
" >/dev/null

  echo "✅ MySQL initialized (idempotent)"
}

phase_state_file() {
  local phase="$1"
  echo "$STATE_DIR/${phase}.done"
}

is_phase_completed() {
  local phase="$1"
  local state_file
  local current_hash
  local saved_hash

  state_file="$(phase_state_file "$phase")"
  [[ -f "$state_file" ]] || return 1
  [[ -f "$PHASES_DIR/$phase" ]] || return 1
  current_hash="$(phase_hash "$phase")"
  saved_hash="$(<"$state_file")"
  [[ "$current_hash" == "$saved_hash" ]]
}

mark_phase_completed() {
  local phase="$1"
  phase_hash "$phase" > "$(phase_state_file "$phase")"
}

check_dependencies() {
  local phase="$1"
  local phase_file="$PHASES_DIR/$phase"
  local dep_line deps dep

  dep_line="$(awk -F': ' '/^# @depends:/{print $2; exit}' "$phase_file")"
  [[ -n "$dep_line" ]] || return 0

  deps="$dep_line"
  for dep in $deps; do
    [[ -f "$PHASES_DIR/$dep" ]] || fail "Dependency phase file not found for $phase: $dep"
    [[ "$dep" != "$phase" ]] || fail "Phase $phase cannot depend on itself"
    if ! is_phase_completed "$dep"; then
      fail "Dependency not satisfied for $phase: $dep"
    fi
  done
}

run_readiness_check() {
  local phase="$1"
  local phase_file="$PHASES_DIR/$phase"
  local ready_cmd

  ready_cmd="$(awk -F': ' '/^# @ready:/{print $2; exit}' "$phase_file")"
  [[ -n "$ready_cmd" ]] || return 0

  echo "⏳ Readiness check for $phase"
  if ! bash -c "$ready_cmd"; then
    fail "Readiness check failed for $phase"
  fi

  echo "✅ Readiness passed for $phase"
}

run_k8s_readiness_if_present() {
  if ! command -v kubectl >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -d "$ROOT/infra/kubernetes" ]]; then
    return 0
  fi

  local manifest
  while IFS= read -r manifest; do
    if ! rg -n "kind:[[:space:]]*Deployment" "$manifest" >/dev/null 2>&1; then
      continue
    fi
    local name ns
    name="$(awk '/^[[:space:]]*name:[[:space:]]*/{print $2; exit}' "$manifest")"
    ns="$(awk '/^[[:space:]]*namespace:[[:space:]]*/{print $2; exit}' "$manifest")"
    [[ -n "$name" ]] || continue
    ns="${ns:-default}"
    kubectl rollout status "deployment/$name" -n "$ns" --timeout=120s >/dev/null
  done < <(find "$ROOT/infra/kubernetes" -type f \( -name '*.yaml' -o -name '*.yml' \))
}

should_skip_phase() {
  local phase="$1"
  if [[ "${MM_SKIP_DOCKER_ACTIONS:-0}" != "1" ]]; then
    return 1
  fi

  case "$phase" in
    70-nginx.sh|85-backup.sh|86-restore.sh|87-dr-test.sh|88-offsite.sh|92-regulator-report.sh|93-settlement-engine.sh|100-bank-reconciliation.sh|101-aml-str-report.sh|103-aml-str-xml.sh|104-bank-settlement.sh|108-release.sh|110-runtest-report.sh)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

print_summary() {
  local total="$1"
  local succeeded="$2"
  local skipped="$3"
  local started_at="$4"
  local finished_at

  finished_at="$(date +%s)"

  echo
  echo "=================================================="
  echo " EXECUTION SUMMARY"
  echo "--------------------------------------------------"
  echo " Total phases planned : $total"
  echo " Total phases success : $succeeded"
  echo " Total phases skipped : $skipped"
  echo " Total phases failed  : $((total - succeeded - skipped))"
  echo " Duration (seconds)   : $((finished_at - started_at))"
  echo "=================================================="
}

run_all() {
  local from_phase="${MM_FROM_PHASE:-${1:-}}"
  local to_phase="${MM_TO_PHASE:-${2:-}}"
  local from_index=0
  local to_index=$(( ${#PHASE_ORDER[@]} - 1 ))
  local i phase started_at total
  local -i planned=0
  local -i succeeded=0
  local -i skipped=0

  validate_env
  init_mysql_if_needed

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

    if should_skip_phase "$phase"; then
      echo
      echo ">>> SKIPPING PHASE: $phase"
      echo "--------------------------------------------------"
      echo "⚠ MM_SKIP_DOCKER_ACTIONS=1 -> skipped docker-dependent phase"
      echo "<<< SKIPPED: $phase"
      skipped=$((skipped + 1))
      continue
    fi

    if [[ "${MM_FORCE_RUN_ALL:-0}" != "1" ]] && is_phase_completed "$phase"; then
      echo
      echo ">>> SKIPPING PHASE: $phase"
      echo "--------------------------------------------------"
      echo "ℹ phase already completed (hash state matches)"
      echo "<<< SKIPPED: $phase"
      skipped=$((skipped + 1))
      continue
    fi

    check_dependencies "$phase"
    run_phase_safe "$phase"
    run_readiness_check "$phase"
    run_k8s_readiness_if_present
    mark_phase_completed "$phase"
    succeeded=$((succeeded + 1))

    if [[ "$phase" == "00-guard.sh" ]]; then
      # load shared assertions after guard passes
      # shellcheck disable=SC1091
      source "$ROOT/generator/lib/assert.sh"
    fi
  done

  print_summary "$total" "$succeeded" "$skipped" "$started_at"

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
    clean-installer)
      local mode="${2:-full}"
      if [[ ! -x "$ROOT/installer/zgaming-ultra-installer.sh" ]]; then
        fail "Installer script missing: $ROOT/installer/zgaming-ultra-installer.sh"
      fi
      bash "$ROOT/installer/zgaming-ultra-installer.sh" "$mode"
      ;;
    test)
      run_phase_safe "00-guard.sh"
      run_phase_safe "110-runtest-report.sh"
      ;;
    doctor)
      run_phase_safe "00-guard.sh"
      ;;
    phase)
      if [[ $# -lt 2 ]]; then
        fail "Missing phase name"
      fi
      validate_env
      init_mysql_if_needed
      check_dependencies "$2"
      run_phase_safe "$2"
      run_readiness_check "$2"
      run_k8s_readiness_if_present
      mark_phase_completed "$2"
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
    scan)
      if ! command -v python3 >/dev/null 2>&1; then
        fail "python3 is required for scan command"
      fi
      python3 "$ROOT/scripts/full_logic_scan.py" --repo-root "$ROOT"
      echo "✅ Logic scan artifacts created under $ROOT/reports"
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
