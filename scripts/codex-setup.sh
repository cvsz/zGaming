#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[setup] Installing deterministic workspace dependencies with pnpm..."
pnpm install --frozen-lockfile=false

echo "[setup] Installing Playwright browsers for deterministic e2e runtime..."
npx playwright install

echo "[setup] Running multi-chain isolation + anomaly checks..."
./scripts/verify-ops-guardrails.sh

echo "[setup] Complete"
