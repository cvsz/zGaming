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
AUDIT_FILE="$REPORT_DIR/audit-report.json"
RELEASE_DIR="$ARTIFACT_DIR/release"
WORKFLOW_FILE="$ARTIFACT_DIR/workflow-plan.txt"

mkdir -p "$REPORT_DIR" "$ARTIFACT_DIR" "$RELEASE_DIR"

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
  ./installer/zgaming-ultra-installer.sh full-project
  ./installer/zgaming-ultra-installer.sh diagnostics
  ./installer/zgaming-ultra-installer.sh audit
  ./installer/zgaming-ultra-installer.sh package
  ./installer/zgaming-ultra-installer.sh plan
  ./installer/zgaming-ultra-installer.sh menu

Modes:
  quick         -> preflight + deterministic generator doctor + metadata extraction
  full          -> quick + meta-master installer pipeline + diagnostics + release package
  full-project  -> strict full mode with hardening + vulnerability scan + audit report
  diagnostics   -> network/container/cloud diagnostics only
  audit         -> metadata manifest + compliance report + SBOM + structured audit JSON
  package       -> reproducible bundle with checksums and version metadata
  plan          -> print pseudo-code workflow for deterministic install pipeline
  menu          -> interactive menu for one-click operator workflows
USAGE
}

print_plan() {
  cat <<'PLAN' | tee "$WORKFLOW_FILE" >/dev/null
clean_install(mode):
  validate shell/runtime/toolchain preflight
  run deterministic doctor baseline
  extract metadata + immutable file hash manifest
  execute compliance and security baseline checks
  emit SPDX-lite SBOM + structured audit report
  if mode in [full, full-project]: run generator installer
  run diagnostics for container/network/time-sync and local stack health
  if mode == full-project: run vulnerability scan (best effort)
  package release artifacts (manifest, compliance, sbom, logs)
PLAN
  echo "🧭 Workflow saved to: $WORKFLOW_FILE"
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

  local strict_mode_count phase_count has_compose has_k8s
  strict_mode_count="$(find "$ROOT/generator" -type f -name '*.sh' -exec awk 'FNR==1, FNR==20 {print}' {} + | rg -c 'set -Eeuo pipefail' || true)"
  phase_count="$(find "$ROOT/generator/phases" -maxdepth 1 -type f -name '*.sh' | wc -l | awk '{print $1}')"
  has_compose=false
  has_k8s=false

  [[ -f "$ROOT/docker-compose.yml" ]] && has_compose=true
  [[ -d "$ROOT/k8s" ]] && has_k8s=true

  cat > "$COMPLIANCE_FILE" <<EOF_COMPLIANCE
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "checks": {
    "strict_mode_occurrences": $strict_mode_count,
    "phase_script_count": $phase_count,
    "has_phase_checksum": $( [[ -f "$ROOT/generator/phases/SHA256SUMS" ]] && echo true || echo false ),
    "has_orchestrator_scaffold": $( [[ -f "$ROOT/core/orchestrator/kernel.ts" ]] && echo true || echo false ),
    "has_gateway": $( [[ -f "$ROOT/api/gateway/server.ts" ]] && echo true || echo false ),
    "has_compose": $has_compose,
    "has_kubernetes_folder": $has_k8s
  }
}
EOF_COMPLIANCE

  log_json "info" "compliance_ready" "report=$COMPLIANCE_FILE"
}

run_hardening_checks() {
  log_json "info" "hardening_checks" "running hardening checks for dns/firewall/ntp"

  {
    echo "== Hardening checks =="
    echo "Date(UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "-- DNS --"
    awk '/^nameserver/{print}' /etc/resolv.conf 2>/dev/null || true
    echo "-- Time sync --"
    timedatectl status 2>/dev/null | sed -n '1,8p' || true
    echo "-- Firewall --"
    if command -v ufw >/dev/null 2>&1; then
      ufw status 2>/dev/null || true
    elif command -v firewall-cmd >/dev/null 2>&1; then
      firewall-cmd --state 2>/dev/null || true
    else
      echo "No supported firewall CLI found (ufw/firewall-cmd)."
    fi
  } | tee -a "$LOG_FILE" >/dev/null
}

write_audit_report() {
  log_json "info" "audit_report" "writing structured audit metadata"

  local git_commit git_branch version docker_version compose_version
  git_commit="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
  git_branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
  version="$(cat "$ROOT/generator/VERSION" 2>/dev/null || echo "unknown")"
  docker_version="$(docker --version 2>/dev/null | sed 's/"//g' || echo "unavailable")"
  compose_version="$(docker compose version 2>/dev/null | sed 's/"//g' || echo "unavailable")"

  cat > "$AUDIT_FILE" <<EOF_AUDIT
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project": "zGaming",
  "version": "$version",
  "git": {
    "branch": "$git_branch",
    "commit": "$git_commit"
  },
  "runtime": {
    "os": "$(uname -s)",
    "kernel": "$(uname -r)",
    "arch": "$(uname -m)",
    "docker": "$docker_version",
    "docker_compose": "$compose_version"
  },
  "artifacts": {
    "manifest": "$MANIFEST_FILE",
    "compliance": "$COMPLIANCE_FILE",
    "sbom": "$SBOM_FILE",
    "workflow": "$WORKFLOW_FILE"
  }
}
EOF_AUDIT
}

run_vulnerability_scan() {
  log_json "info" "vuln_scan" "running vulnerability scan (best effort)"
  if command -v trivy >/dev/null 2>&1; then
    trivy fs --quiet --scanners vuln,misconfig --format table "$ROOT" | tee -a "$LOG_FILE" >/dev/null || true
  else
    echo "⚠️ trivy not installed, skipping vulnerability scan"
    log_json "warn" "vuln_scan_skipped" "trivy not installed"
  fi
}

build_release_package() {
  log_json "info" "release_package" "building reproducible release bundle"

  local version ts bundle checksum_file
  version="$(cat "$ROOT/generator/VERSION" 2>/dev/null || echo "unknown")"
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  bundle="$RELEASE_DIR/zgaming-installer-bundle-${version}-${ts}.zip"
  checksum_file="$bundle.sha256"

  (
    cd "$ROOT"
    zip -q -r "$bundle" \
      README.md CHANGELOG.md \
      installer/reports installer/artifacts \
      generator/VERSION
  )

  sha256sum "$bundle" > "$checksum_file"
  log_json "info" "release_bundle_ready" "bundle=$bundle checksum=$checksum_file"
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
  require_bins bash git sha256sum awk sed find curl docker rg zip
  check_runtime
  print_plan
  (
    cd "$ROOT"
    bash ./generator/meta-master.sh doctor
  )
  extract_repo_metadata
  compliance_checks
  generate_sbom_lite
  write_audit_report
  log_json "info" "quick_complete" "quick mode finished"
}

run_full() {
  run_quick
  (
    cd "$ROOT"
    bash ./generator/meta-master.sh installer
  )
  run_hardening_checks
  run_diagnostics
  build_release_package
  log_json "info" "full_complete" "full mode finished"
}

run_full_project() {
  run_full
  run_vulnerability_scan
  log_json "info" "full_project_complete" "full-project mode finished"
}

menu() {
  echo "Select workflow:"
  echo "  1) Quick"
  echo "  2) Full"
  echo "  3) Full Project"
  echo "  4) Diagnostics"
  echo "  5) Audit"
  echo "  6) Package"
  echo "  7) Plan"
  read -r -p "Choice [1-7]: " choice

  case "$choice" in
    1) run_quick ;;
    2) run_full ;;
    3) run_full_project ;;
    4) run_diagnostics ;;
    5) extract_repo_metadata; compliance_checks; generate_sbom_lite; print_plan; write_audit_report ;;
    6) build_release_package ;;
    7) print_plan ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
}

main() {
  local cmd="${1:-menu}"

  print_banner
  case "$cmd" in
    quick) run_quick ;;
    full) run_full ;;
    full-project) run_full_project ;;
    diagnostics) require_bins bash git sha256sum awk sed find curl docker rg; check_runtime; run_diagnostics ;;
    audit) require_bins bash git sha256sum awk sed find curl rg; extract_repo_metadata; compliance_checks; generate_sbom_lite; print_plan; write_audit_report ;;
    package) require_bins bash git sha256sum zip; build_release_package ;;
    plan) print_plan ;;
    menu) require_bins bash git sha256sum awk sed find curl docker rg zip; check_runtime; menu ;;
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
  echo "🧪 Audit: $AUDIT_FILE"
  echo "🪪 SBOM: $SBOM_FILE"
}

main "$@"
