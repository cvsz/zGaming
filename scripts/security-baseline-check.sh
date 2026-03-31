#!/usr/bin/env bash
set -euo pipefail

failures=0

check_no_tracked_paths() {
  local pattern="$1"
  local label="$2"
  local tracked

  tracked="$(git ls-files "$pattern")"
  if [[ -n "$tracked" ]]; then
    echo "[FAIL] Tracked ${label} found:" >&2
    echo "$tracked" >&2
    failures=$((failures + 1))
  else
    echo "[PASS] No tracked ${label}."
  fi
}

check_secret_manifests() {
  local suspicious
  suspicious="$(rg --glob '*.yaml' --glob '*.yml' --files-with-matches 'kind:\s*Secret|JWT_SECRET|jwt-secret' infra infrastructure k8s 2>/dev/null || true)"

  if [[ -z "$suspicious" ]]; then
    echo "[PASS] No potentially risky Secret manifests detected in infra directories."
    return
  fi

  echo "[WARN] Potential Secret manifests or JWT key references detected:" >&2
  echo "$suspicious" >&2
  echo "       Ensure values are injected at deploy time and not committed inline." >&2
}

check_no_tracked_paths 'node_modules/**' 'node_modules directories'
check_no_tracked_paths '*.log' 'log files'
check_no_tracked_paths 'logs/**' 'log directories'
check_no_tracked_paths 'pids/**' 'PID directories'

check_secret_manifests

if [[ "$failures" -gt 0 ]]; then
  echo "Security baseline check failed with ${failures} blocking issue(s)." >&2
  exit 1
fi

echo 'Security baseline check passed.'
