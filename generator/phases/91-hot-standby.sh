#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 91] HOT-STANDBY MULTI-REGION"

MODE="${1:-status}" # status | promote | demote

if [[ "$MODE" == "status" ]]; then
  echo "APP_ROLE=${APP_ROLE:-unknown}"
  exit 0
fi

if [[ "$MODE" == "promote" ]]; then
  echo ">> PROMOTING STANDBY TO PRIMARY"
  kubectl scale deploy api --replicas=3
  kubectl exec mysql -- mysql -e "STOP SLAVE; RESET SLAVE ALL;"
  export APP_ROLE=primary
  echo "APP_ROLE=primary" >> .env
fi

if [[ "$MODE" == "demote" ]]; then
  echo ">> DEMOTING TO STANDBY"
  export APP_ROLE=standby
  sed -i 's/APP_ROLE=.*/APP_ROLE=standby/' .env
fi

echo "✅ Hot-standby operation complete"