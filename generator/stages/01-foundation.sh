#!/bin/bash
export STAGE_NAME="01-foundation"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if check_stage_state "$STAGE_NAME"; then exit 0; fi

log "INFO" "Starting Stage 1: Foundation"
progress "Foundation (00–10)"

phases='"00-guard.sh","10-backend.sh"'

"$PHASES_DIR/00-guard.sh" || { rollback_stage; exit 1; }
"$PHASES_DIR/10-backend.sh" || { rollback_stage; exit 1; }

generate_manifest "$STAGE_NAME" "$phases"
mark_stage_completed "$STAGE_NAME"
log "SUCCESS" "Stage 1 completed."
