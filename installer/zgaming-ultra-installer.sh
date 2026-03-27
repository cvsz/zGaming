#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="$SCRIPT_DIR/reports"
ARTIFACT_DIR="$SCRIPT_DIR/artifacts"
LOG_FILE="$REPORT_DIR/install-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
MANIFEST_FILE="$ARTIFACT_DIR/repo-manifest.sha256"
SBOM_FILE="$ARTIFACT_DIR/sbom-lite.spdx.json"
COMPLIANCE_FILE="$REPORT_DIR/compliance-report.json"

mkdir -p "$REPORT_DIR" "$ARTIFACT_DIR"

log_json() {
  local level="$1" event="$2" details="${3:-}"
  printf '{"ts":"%s","level":"%s","event":"%s","details":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$event" "${details//\"/\\\"}" | tee -a "$LOG_FILE" >/dev/null
}

print_banner() {
  cat <<'BANNER'
=====================================================
 zGaming Ultra Meta Platform :: Clean Installer (2026)
 deterministic | security-first | compliance-ready
=====================================================
BANNER
}

usage() {
  cat <<'USAGE'
Usage:
  ./installer/zgaming-ultra-installer.sh quick
  ./installer/zgaming-ultra-installer.sh full
  ./installer/zgaming-ultra-installer.sh diagnostics
  ./installer/zgaming-ultra-installer.sh audit
  ./installer/zgaming-ultra-installer.sh menu

Modes:
  quick        -> preflight + deterministic generator doctor + metadata extraction
  full         -> quick + meta-master installer pipeline + compliance checks + SBOM
  diagnostics  -> network/container/cloud diagnostics only
  audit        -> metadata manifest + compliance report + SBOM generation
  menu         -> interactive menu for one-click operator workflows
USAGE
}

rollback() {
  local code="$?"
  if (( code != 0 )); then
    log_json "error" "rollback" "installer failure detected, preserving logs only"
    echo "❌ Installer failed. Review: $LOG_FILE"
  fi
  return "$code"
}
trap rollback EXIT

require_bins() {
  local missing=0
  local bins=("$@")
  if (( ${#bins[@]} == 0 )); then
    bins=(bash git sha256sum awk sed find curl rg)
  fi
  for bin in "${bins[@]}"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "❌ Missing required binary: $bin"
      log_json "error" "missing_binary" "$bin"
      missing=1
    fi
  done
  (( missing == 0 ))
}

check_runtime() {
  log_json "info" "runtime_check" "checking docker and repository state"

  if ! docker info >/dev/null 2>&1; then
    echo "⚠️ Docker daemon unavailable (non-fatal for audit mode)"
    log_json "warn" "docker_unavailable" "docker daemon not reachable"
  fi

  if [[ ! -f "$ROOT/generator/meta-master.sh" ]]; then
    echo "❌ generator/meta-master.sh missing"
    exit 1
  fi
}

extract_repo_metadata() {
  log_json "info" "metadata_extraction" "building repository manifest and topology"

  (
    cd "$ROOT"
    : > "$MANIFEST_FILE"
    while IFS= read -r -d '' file; do
      sha256sum "$file" >> "$MANIFEST_FILE"
    done < <(find . -type f \
      -not -path './.git/*' \
      -not -path './installer/reports/*' \
      -not -path './installer/artifacts/*' \
      -print0 | sort -z)
  )

  local file_count
  file_count="$(wc -l < "$MANIFEST_FILE" | awk '{print $1}')"
  log_json "info" "metadata_manifest_ready" "files_hashed=$file_count manifest=$MANIFEST_FILE"
}

generate_sbom_lite() {
  log_json "info" "sbom_generation" "generating lightweight SPDX-compatible SBOM"

  local version
  version="$(cat "$ROOT/generator/VERSION" 2>/dev/null || echo "unknown")"

  cat > "$SBOM_FILE" <<EOF_SBOM
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "zGaming-ultra-meta-sbom-lite",
  "documentNamespace": "https://zgaming.local/spdx/$(date -u +%Y%m%dT%H%M%SZ)",
  "creationInfo": {
    "creators": [
      "Tool: zgaming-ultra-installer"
    ],
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  },
  "packages": [
    {
      "name": "zGaming",
      "SPDXID": "SPDXRef-Package-zGaming",
      "versionInfo": "$version",
      "downloadLocation": "NOASSERTION",
      "filesAnalyzed": false,
      "licenseConcluded": "NOASSERTION",
      "supplier": "Organization: zGaming"
    }
  ]
}
EOF_SBOM

  log_json "info" "sbom_ready" "sbom=$SBOM_FILE"
}

compliance_checks() {
  log_json "info" "compliance_check" "running deterministic + security baseline checks"

  local strict_mode_count phase_count
  strict_mode_count="$(find "$ROOT/generator" -type f -name '*.sh' -exec awk 'FNR==1, FNR==15 {print}' {} + | rg -c 'set -Eeuo pipefail' || true)"
  phase_count="$(find "$ROOT/generator/phases" -maxdepth 1 -type f -name '*.sh' | wc -l | awk '{print $1}')"

  cat > "$COMPLIANCE_FILE" <<EOF_COMPLIANCE
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "checks": {
    "strict_mode_occurrences": $strict_mode_count,
    "phase_script_count": $phase_count,
    "has_phase_checksum": $( [[ -f "$ROOT/generator/phases/SHA256SUMS" ]] && echo true || echo false ),
    "has_orchestrator_scaffold": $( [[ -f "$ROOT/core/orchestrator/kernel.ts" ]] && echo true || echo false ),
    "has_gateway": $( [[ -f "$ROOT/api/gateway/server.ts" ]] && echo true || echo false )
  }
}
EOF_COMPLIANCE

  log_json "info" "compliance_ready" "report=$COMPLIANCE_FILE"
}

run_diagnostics() {
  log_json "info" "diagnostics" "running network/container diagnostics"
  echo "== Diagnostics =="
  echo "Date(UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Host: $(uname -a)"

  if command -v docker >/dev/null 2>&1; then
    echo "-- docker compose version --"
    docker compose version || true
    echo "-- docker ps --"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' || true
  fi

  echo "-- healthcheck probe --"
  if [[ -x "$ROOT/scripts/healthcheck.sh" ]]; then
    "$ROOT/scripts/healthcheck.sh" http://localhost/api/healthz.php || true
  else
    curl -fsS http://localhost/api/healthz.php >/dev/null || true
  fi
}

run_quick() {
  require_bins bash git sha256sum awk sed find curl docker rg
  check_runtime
  (
    cd "$ROOT"
    bash ./generator/meta-master.sh doctor
  )
  extract_repo_metadata
  compliance_checks
  generate_sbom_lite
  log_json "info" "quick_complete" "quick mode finished"
}

run_full() {
  run_quick
  (
    cd "$ROOT"
    bash ./generator/meta-master.sh installer
  )
  run_diagnostics
  log_json "info" "full_complete" "full mode finished"
}

menu() {
  echo "Select workflow:"
  echo "  1) Quick"
  echo "  2) Full"
  echo "  3) Diagnostics"
  echo "  4) Audit"
  read -r -p "Choice [1-4]: " choice

  case "$choice" in
    1) run_quick ;;
    2) run_full ;;
    3) run_diagnostics ;;
    4) extract_repo_metadata; compliance_checks; generate_sbom_lite ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
}

main() {
  local cmd="${1:-menu}"

  print_banner
  case "$cmd" in
    quick) run_quick ;;
    full) run_full ;;
    diagnostics) require_bins bash git sha256sum awk sed find curl docker rg; check_runtime; run_diagnostics ;;
    audit) require_bins bash git sha256sum awk sed find curl rg; extract_repo_metadata; compliance_checks; generate_sbom_lite ;;
    menu) require_bins bash git sha256sum awk sed find curl docker rg; check_runtime; menu ;;
    -h|--help|help) usage ;;
    *)
      echo "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac

  echo "✅ Completed. Logs: $LOG_FILE"
  echo "📦 Manifest: $MANIFEST_FILE"
  echo "🧾 Compliance: $COMPLIANCE_FILE"
  echo "🪪 SBOM: $SBOM_FILE"
}

main "$@"
