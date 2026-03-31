#!/bin/bash
export STAGE_NAME="02-core-systems"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if check_stage_state "$STAGE_NAME"; then exit 0; fi

log "INFO" "Starting Stage 2: Core Systems"
progress "Core Systems (20–38)"

phases='"20-auth.sh","30-wallet.sh","35-fx.sh","36-fx-live.sh","37-currency-lock.sh","38-multi-wallet.sh"'

for p in 20-auth 30-wallet 35-fx 36-fx-live 37-currency-lock 38-multi-wallet; do
    "$PHASES_DIR/${p}.sh" || { rollback_stage; exit 1; }
done

generate_manifest "$STAGE_NAME" "$phases"
mark_stage_completed "$STAGE_NAME"
log "SUCCESS" "Stage 2 completed."
