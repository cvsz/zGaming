#!/bin/bash
# generator/stages/lib/common.sh – Shared utilities (final merged version)

set -Eeuo pipefail

export ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)}"
STATE_DIR="$ROOT/.meta-master-state"
LOG_FILE="$ROOT/logs/generator-stages.log"
MANIFEST_DIR="$ROOT/manifests"
REPORT_DIR="$ROOT/reports"
PHASES_DIR="$ROOT/generator/phases"

mkdir -p "$STATE_DIR" "$MANIFEST_DIR" "$REPORT_DIR" "$(dirname "$LOG_FILE")"

STATE_FILE="$STATE_DIR/stages.json"
[[ ! -f "$STATE_FILE" ]] && echo '{"stages":{}}' > "$STATE_FILE"

log() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$ts] [$level] [$STAGE_NAME] $msg" | tee -a "$LOG_FILE"
}

progress() {
    echo -e "\033[1;36m[PROGRESS] $1\033[0m"
}

check_stage_state() {
    local name="$1"
    if [[ "$(jq -r ".stages[\"$name\"] // \"pending\"" "$STATE_FILE")" == "completed" && "${FORCE_STAGE:-0}" != "1" ]]; then
        log "INFO" "Stage already completed. Skipping."
        return 0
    fi
    return 1
}

mark_stage_completed() {
    local name="$1"
    jq --arg s "$name" '.stages[$s] = "completed"' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    log "SUCCESS" "Stage marked as completed."
}

generate_file_checksums() {
    find "$ROOT" \( -name ".meta-master-state" -o -name "logs" -o -name "manifests" -o -name "reports" \) -prune -o -type f \( -name "*.php" -o -name "*.ts" -o -name "*.tsx" -o -name "*.sh" -o -name "*.json" -o -name "*.yml" -o -name "*.yaml" \) -print0 | while IFS= read -r -d '' f; do
        local rel="${f#$ROOT/}"
        local sha
        sha=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')
        echo "{\"path\":\"$rel\",\"sha256\":\"$sha\"}"
    done | paste -sd, -
}

generate_manifest() {
    local name="$1"
    local phases="$2"
    local file="$MANIFEST_DIR/stage-${name}-manifest.json"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local checksums
    checksums=$(generate_file_checksums)

    cat > "$file" <<EOM
{
  "stage": "${name}",
  "completed_at": "${ts}",
  "phases_executed": [${phases}],
  "status": "completed",
  "manifest_version": "2.2",
  "checksums": [${checksums}]
}
EOM
    log "INFO" "Manifest with checksums generated: $file"
}

rollback_stage() {
    log "WARN" "Rollback triggered for stage $STAGE_NAME – no custom actions defined."
}
