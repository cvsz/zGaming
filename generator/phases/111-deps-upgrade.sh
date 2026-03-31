#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'\n\t'

echo "[PHASE 111] DEPENDENCY UPGRADE PREP"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="$ROOT/reports"
REPORT_FILE="$REPORT_DIR/dependency-upgrade-plan.md"

mkdir -p "$REPORT_DIR"

PNPM_CMD="pnpm update --latest"
COMPOSER_CMD="composer update"
GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat > "$REPORT_FILE" <<PLAN
# Dependency Upgrade Plan (Generated)

Generated at: $GENERATED_AT

## Commands

- Node workspace upgrades: $PNPM_CMD
- PHP Composer upgrades (when composer.json exists): $COMPOSER_CMD

## Container image targets

- PHP base image: php:8.4-cli-alpine
- Docker Compose backend: php:8.4-apache
- Docker Compose database: mysql:8.4.0
- Docker Compose nginx: nginx:1.27.5-alpine

## Follow-up

1. Execute upgrade commands in a clean branch.
2. Run pnpm test and npm run audit:logic.
3. Rebuild runtime images with digest pinning for release builds.
PLAN

if command -v pnpm >/dev/null 2>&1; then
  echo "[INFO] Running pnpm install to refresh lockfile metadata"
  if ! (cd "$ROOT" && pnpm install --lockfile-only >/dev/null); then
    echo "[WARN] pnpm lockfile refresh failed; continue with generated plan"
  fi
else
  echo "[WARN] pnpm not found; skipped lockfile refresh"
fi

echo "[DONE] Dependency upgrade plan generated at $REPORT_FILE"
