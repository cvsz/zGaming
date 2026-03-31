#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHAIN_VALIDATION_FILE="$ROOT_DIR/modules/wallet/chain-validation.ts"
ANOMALY_MONITOR_FILE="$ROOT_DIR/frontend-admin/src/transaction-review.ts"

if [[ ! -f "$CHAIN_VALIDATION_FILE" ]]; then
  echo "[FAIL] Missing strict chain validation module"
  exit 1
fi

if ! rg -q "Strict chainId validation failed" "$CHAIN_VALIDATION_FILE"; then
  echo "[FAIL] strict chainId guard not found"
  exit 1
fi

if [[ ! -f "$ANOMALY_MONITOR_FILE" ]]; then
  echo "[FAIL] Missing anomaly monitoring validator"
  exit 1
fi

if ! rg -q "invalid ETH chainId|invalid SOL chainId" "$ANOMALY_MONITOR_FILE"; then
  echo "[FAIL] anomaly checks for chain validation not found"
  exit 1
fi

echo "[PASS] Multi-chain isolation and anomaly monitoring checks are in place"
