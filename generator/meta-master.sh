#!/usr/bin/env bash
# generator/meta-master.sh – Final merged orchestrator

set -Eeuo pipefail
export ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export STAGE_NAME="${STAGE_NAME:-meta-master}"
export PHASE_NAME="${PHASE_NAME:-${1:-}}"
export CURRENT_STAGE="${CURRENT_STAGE:-$STAGE_NAME}"
export MM_FROM_PHASE="${MM_FROM_PHASE:-}"
export MM_TO_PHASE="${MM_TO_PHASE:-}"
source "$ROOT/generator/stages/lib/common.sh"

# Optional pre-flight asserts:
# - stage-local assert lib (if present) runs by default
# - legacy generator/lib/assert.sh is only executed when explicitly requested,
#   because it validates generated artifacts that do not exist on first run.
if [[ -f "$ROOT/generator/stages/lib/assert.sh" ]]; then
    source "$ROOT/generator/stages/lib/assert.sh"
elif [[ "${MM_RUN_LEGACY_PREFLIGHT_ASSERTS:-0}" == "1" && -f "$ROOT/generator/lib/assert.sh" ]]; then
    source "$ROOT/generator/lib/assert.sh"
fi

require_var() {
    local var_name="$1"
    if [[ -z "${!var_name:-}" ]]; then
        echo "ERROR: Required variable '${var_name}' is not set." >&2
        exit 1
    fi
}

print_header() {
    echo "=================================================="
    echo "  DEEP IMPACT DRIVE – FULLY MERGED META-MASTER (FINAL)"
    echo "=================================================="
}

case "${1:-all}" in
    all)
        require_var STAGE_NAME
        print_header
        log "INFO" "Initiating full merged generation pipeline"
        start_time=$(date +%s)

        for stage in "$ROOT/generator/stages"/0[1-6]-*.sh; do
            bash "$stage" || exit 1
        done

        end_time=$(date +%s)
        duration=$((end_time - start_time))

        # Final HTML report
        cat > "$ROOT/reports/final-generation-report.html" <<EOM
<!DOCTYPE html>
<html>
<head><title>Deep Impact Drive – Generation Report</title></head>
<body>
<h1>Platform Generation Completed Successfully</h1>
<p><strong>Total duration:</strong> ${duration} seconds</p>
<p><strong>Completed at:</strong> $(date -u)</p>
<p>All stages executed. Manifests and checksums available in generator/manifests/.</p>
<p>Next step: docker compose up -d --build</p>
</body>
</html>
EOM

        log "SUCCESS" "Full generation completed in ${duration} seconds."
        echo "HTML report generated: $ROOT/reports/final-generation-report.html"
        echo "Next recommended action: docker compose up -d --build"
        ;;
    stage)
        stage_file="$ROOT/generator/stages/${2}.sh"
        if [[ -f "$stage_file" ]]; then
            bash "$stage_file"
        else
            log "ERROR" "Stage not found: $2"
            exit 1
        fi
        ;;
    clean)
        rm -rf "$ROOT/.meta-master-state" "$ROOT/manifests" "$ROOT/logs" "$ROOT/reports"
        mkdir -p "$ROOT/.meta-master-state" "$ROOT/manifests" "$ROOT/logs" "$ROOT/reports"
        echo '{"stages":{}}' > "$ROOT/.meta-master-state/stages.json"
        echo "State and artifacts reset."
        ;;
    *)
        echo "Usage: ./generator/meta-master.sh [all | stage <N> | clean]"
        ;;
esac
