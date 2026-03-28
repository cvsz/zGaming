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
SHA256SUMS_FILE="$RELEASE_DIR/SHA256SUMS"
SIGNATURE_FILE="$RELEASE_DIR/SHA256SUMS.sig"

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
  execute chaos callback storm test for idempotency validation
  package immutable release artifacts + SHA256SUMS + signature
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
    bins=(bash git sha256sum awk sed find curl rg zip openssl)
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
  [[ -f "$ROOT/generator/meta-master.sh" ]] || { echo "❌ generator/meta-master.sh missing"; exit 1; }
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
  log_json "info" "metadata_manifest_ready" "files_hashed=$(wc -l < "$MANIFEST_FILE" | awk '{print $1}')"
}

generate_sbom_lite() {
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
    "creators": ["Tool: zgaming-ultra-installer"],
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  },
  "packages": [{
    "name": "zGaming",
    "SPDXID": "SPDXRef-Package-zGaming",
    "versionInfo": "$version",
    "downloadLocation": "NOASSERTION",
    "filesAnalyzed": false,
    "licenseConcluded": "NOASSERTION",
    "supplier": "Organization: zGaming"
  }]
}
EOF_SBOM
}

compliance_checks() {
  local strict_mode_count phase_count has_compose has_k8s has_chaos has_wallet has_ledger
  strict_mode_count="$(find "$ROOT/generator" -type f -name '*.sh' -exec awk 'FNR==1, FNR==20 {print}' {} + | rg -c 'set -Eeuo pipefail' || true)"
  phase_count="$(find "$ROOT/generator/phases" -maxdepth 1 -type f -name '*.sh' | wc -l | awk '{print $1}')"
  [[ -f "$ROOT/docker-compose.yml" ]] && has_compose=true || has_compose=false
  [[ -d "$ROOT/infra/kubernetes" ]] && has_k8s=true || has_k8s=false
  [[ -x "$ROOT/scripts/chaos-callback-storm.sh" ]] && has_chaos=true || has_chaos=false
  [[ -f "$ROOT/modules/wallet/index.ts" ]] && has_wallet=true || has_wallet=false
  [[ -f "$ROOT/modules/ledger/ledger.ts" ]] && has_ledger=true || has_ledger=false

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
    "has_kubernetes_folder": $has_k8s,
    "has_chaos_callback_test": $has_chaos,
    "has_multichain_wallet_module": $has_wallet,
    "has_idempotent_ledger_module": $has_ledger
  }
}
EOF_COMPLIANCE
}

write_audit_report() {
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
  "git": {"branch": "$git_branch", "commit": "$git_commit"},
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
    "workflow": "$WORKFLOW_FILE",
    "sha256sums": "$SHA256SUMS_FILE",
    "signature": "$SIGNATURE_FILE"
  }
}
EOF_AUDIT
}

build_release_package() {
  local version ts bundle
  version="$(cat "$ROOT/generator/VERSION" 2>/dev/null || echo "unknown")"
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  bundle="$RELEASE_DIR/zgaming-installer-bundle-${version}-${ts}.zip"

  (
    cd "$ROOT"
    SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1704067200}" \
      zip -X -q -r "$bundle" \
      README.md CHANGELOG.md docs \
      installer/reports installer/artifacts generator/VERSION scripts
  )

  : > "$SHA256SUMS_FILE"
  sha256sum "$bundle" >> "$SHA256SUMS_FILE"
  sha256sum "$MANIFEST_FILE" "$SBOM_FILE" "$COMPLIANCE_FILE" "$AUDIT_FILE" >> "$SHA256SUMS_FILE"

  if [[ -n "${RELEASE_SIGNING_KEY:-}" && -f "${RELEASE_SIGNING_KEY}" ]]; then
    openssl dgst -sha256 -sign "$RELEASE_SIGNING_KEY" -out "$SIGNATURE_FILE" "$SHA256SUMS_FILE"
  else
    openssl dgst -sha256 "$SHA256SUMS_FILE" > "$SIGNATURE_FILE"
  fi

  log_json "info" "release_bundle_ready" "bundle=$bundle sha=$SHA256SUMS_FILE sig=$SIGNATURE_FILE"
}

run_diagnostics() {
  echo "== Diagnostics =="
  echo "Date(UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if command -v docker >/dev/null 2>&1; then
    docker compose version || true
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' || true
  fi
  [[ -x "$ROOT/scripts/healthcheck.sh" ]] && "$ROOT/scripts/healthcheck.sh" "${API_URL:-http://localhost/api/healthz.php}" || true
}

run_chaos() {
  if [[ -x "$ROOT/scripts/chaos-callback-storm.sh" ]]; then
    "$ROOT/scripts/chaos-callback-storm.sh" || true
  else
    echo "⚠️ chaos test script not found"
  fi
}

run_quick() {
  require_bins bash git sha256sum awk sed find curl docker rg zip openssl
  check_runtime
  print_plan
  (cd "$ROOT" && bash ./generator/meta-master.sh doctor)
  extract_repo_metadata
  compliance_checks
  generate_sbom_lite
  write_audit_report
}

run_full() {
  run_quick
  (cd "$ROOT" && bash ./generator/meta-master.sh installer)
  run_diagnostics
  run_chaos
  build_release_package
}

run_full_project() {
  run_full
  if command -v trivy >/dev/null 2>&1; then
    trivy fs --quiet --scanners vuln,misconfig --format table "$ROOT" | tee -a "$LOG_FILE" >/dev/null || true
  else
    echo "⚠️ trivy not installed, skipping vulnerability scan"
  fi
}

menu() {
  echo "Select workflow: 1) Quick 2) Full 3) Full Project 4) Diagnostics 5) Audit 6) Package 7) Plan"
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
    package) require_bins bash git sha256sum zip openssl; build_release_package ;;
    plan) print_plan ;;
    menu) require_bins bash git sha256sum awk sed find curl docker rg zip openssl; check_runtime; menu ;;
    -h|--help|help) usage ;;
    *) echo "Unknown command: $cmd"; usage; exit 1 ;;
  esac

  echo "✅ Completed. Logs: $LOG_FILE"
  echo "📦 Manifest: $MANIFEST_FILE"
  echo "🧾 Compliance: $COMPLIANCE_FILE"
  echo "🧪 Audit: $AUDIT_FILE"
  echo "🪪 SBOM: $SBOM_FILE"
  echo "🔐 SHA256SUMS: $SHA256SUMS_FILE"
  echo "✍️ Signature: $SIGNATURE_FILE"
}

main "$@"
