#!/bin/bash
export STAGE_NAME="05-risk-compliance"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if check_stage_state "$STAGE_NAME"; then exit 0; fi

log "INFO" "Starting Stage 5: Risk & Compliance"
progress "Risk & Compliance"

phases='"97-responsible-gaming.sh","98-risk-engine.sh","100-bank-reconciliation.sh","101-aml-str-report.sh","102-provider-certification.sh","103-aml-str-xml.sh","104-bank-settlement.sh","105-compliance-dashboard.sh"'

for p in 97-responsible-gaming 98-risk-engine 100-bank-reconciliation 101-aml-str-report 102-provider-certification 103-aml-str-xml 104-bank-settlement 105-compliance-dashboard; do
    run_phase "${p}.sh" || { rollback_stage; exit 1; }
done

generate_manifest "$STAGE_NAME" "$phases"
mark_stage_completed "$STAGE_NAME"
log "SUCCESS" "Stage 5 completed."
