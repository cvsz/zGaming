#!/bin/bash
export STAGE_NAME="04-operations-auditability"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if check_stage_state "$STAGE_NAME"; then exit 0; fi

log "INFO" "Starting Stage 4: Operations & Auditability"
progress "Operations & Auditability"

phases='"80-security.sh","85-backup.sh","86-restore.sh","87-dr-test.sh","88-offsite.sh","92-regulator-report.sh","93-settlement-engine.sh","94-uat-checklist.sh","106-auditor-handover.sh","107-meta-orchestrator.sh","108-release.sh","109-institutional-finance.sh","111-deps-upgrade.sh","110-runtest-report.sh"'

for p in 80-security 85-backup 86-restore 87-dr-test 88-offsite 92-regulator-report 93-settlement-engine 94-uat-checklist 106-auditor-handover 107-meta-orchestrator 108-release 109-institutional-finance 111-deps-upgrade 110-runtest-report; do
    run_phase "${p}.sh" || { rollback_stage; exit 1; }
done

generate_manifest "$STAGE_NAME" "$phases"
mark_stage_completed "$STAGE_NAME"
log "SUCCESS" "Stage 4 completed."
