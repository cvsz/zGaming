#!/usr/bin/env bash
# SELF-HEALING ORCHESTRATOR (dependency graph + auto recovery)
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${PROJECT_ROOT}/.meta-state"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] $2"; }

# =========================
# DEPENDENCY GRAPH
# =========================
declare -A DEPS
DEPS[85-backup]="db"
DEPS[86-restore]="db"
DEPS[90-cloudflare]="network"
DEPS[95-k8s]="docker"

# =========================
# HEALTH CHECKS
# =========================

check_docker() {
  docker info >/dev/null 2>&1
}

check_db() {
  docker exec casino-db mysqladmin ping -h 127.0.0.1 --silent >/dev/null 2>&1
}

check_network() {
  ping -c1 1.1.1.1 >/dev/null 2>&1
}

# =========================
# AUTO RECOVERY
# =========================

recover_docker() {
  log WARN "Docker not ready -> restarting..."
  sudo systemctl restart docker
  sleep 5
}

recover_db() {
  log WARN "DB not ready -> attempting recovery..."

  if docker ps -a --format '{{.Names}}' | grep -q '^casino-db$'; then
    docker start casino-db || true
  else
    log WARN "Recreating DB container..."
    docker run -d \
      --name casino-db \
      -e MYSQL_ROOT_PASSWORD=root \
      -e MYSQL_DATABASE=casino \
      -p 3306:3306 \
      mysql:8
  fi

  for _ in {1..30}; do
    if check_db; then
      log INFO "DB recovered"
      return 0
    fi
    sleep 2
  done

  log ERROR "DB recovery failed"
  return 1
}

recover_network() {
  log WARN "Network issue detected"
}

# =========================
# VALIDATOR
# =========================

ensure_dep() {
  local dep=$1

  case "$dep" in
    docker)
      check_docker || recover_docker
      ;;
    db)
      check_db || recover_db
      ;;
    network)
      check_network || recover_network
      ;;
  esac
}

# =========================
# PHASE RUNNER (SAFE)
# =========================

run_phase() {
  local phase=$1
  local dep=${DEPS[$phase]:-}

  log INFO "Running phase: $phase"

  if [[ -n "$dep" ]]; then
    log INFO "Checking dependency: $dep"
    ensure_dep "$dep"
  fi

  if bash "${PROJECT_ROOT}/phases/$phase.sh"; then
    log INFO "$phase success"
    echo "$phase" >> "$STATE_FILE"
  else
    log ERROR "$phase failed -> attempting auto-heal + retry"

    if [[ -n "$dep" ]]; then
      ensure_dep "$dep"
    fi

    if bash "${PROJECT_ROOT}/phases/$phase.sh"; then
      log INFO "$phase success after retry"
      echo "$phase" >> "$STATE_FILE"
    else
      log ERROR "$phase failed after retry -> abort"
      exit 1
    fi
  fi
}

# =========================
# MAIN PIPELINE
# =========================

PHASES=(
  80-security
  85-backup
  86-restore
  90-cloudflare
)

log INFO "SELF-HEALING META-MASTER START"

# preflight
ensure_dep docker
ensure_dep network

for phase in "${PHASES[@]}"; do
  run_phase "$phase"
done

log INFO "PIPELINE COMPLETE"
