#!/usr/bin/env bash
# generator/meta-master.sh – Final merged orchestrator

set -Eeuo pipefail
export ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/generator/stages/lib/common.sh"

print_header() {
    echo "=================================================="
    echo "  DEEP IMPACT DRIVE – FULLY MERGED META-MASTER (FINAL)"
    echo "=================================================="
}

case "${1:-all}" in
    all)
        print_header
        log "INFO" "Initiating full merged generation pipeline"
        start_time=$(date +%s)

        for stage in "$ROOT/generator/stages"/0[1-6]-*.sh; do
            "$stage" || exit 1
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
        "$ROOT/generator/stages/${2}.sh"
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
