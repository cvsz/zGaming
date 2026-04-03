#!/bin/bash
export STAGE_NAME="06-scale-reliability"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if check_stage_state "$STAGE_NAME"; then exit 0; fi

log "INFO" "Starting Stage 6: Scale & Reliability"
progress "Scale & Reliability"

phases='"90-cloudflare.sh","91-hot-standby.sh","95-k8s.sh","96-bank-psp.sh","107-meta-orchestrator.sh","111-deps-upgrade.sh","110-runtest-report.sh"'

for p in 90-cloudflare 91-hot-standby 95-k8s 96-bank-psp 107-meta-orchestrator 111-deps-upgrade 110-runtest-report; do
    run_phase "${p}.sh" || { rollback_stage; exit 1; }
done

generate_manifest "$STAGE_NAME" "$phases"
mark_stage_completed "$STAGE_NAME"
log "SUCCESS" "Stage 6 completed."
