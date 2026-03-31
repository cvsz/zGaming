#!/bin/bash
export STAGE_NAME="03-growth-features"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if check_stage_state "$STAGE_NAME"; then exit 0; fi

log "INFO" "Starting Stage 3: Growth Features"
progress "Growth Features (40–60)"

phases='"40-providers.sh","50-callbacks.sh","60-frontend.sh"'

for p in 40-providers 50-callbacks 60-frontend; do
    "$PHASES_DIR/${p}.sh" || { rollback_stage; exit 1; }
done

generate_manifest "$STAGE_NAME" "$phases"
mark_stage_completed "$STAGE_NAME"
log "SUCCESS" "Stage 3 completed."
