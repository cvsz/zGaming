#!/usr/bin/env bash
# CONTINUOUS SELF-HEAL DAEMON
set -Eeuo pipefail

while true; do
  if ! docker ps --format '{{.Names}}' | grep -q '^casino-db$'; then
    echo "[AUTOHEAL] restarting DB..."
    docker start casino-db || true
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "[AUTOHEAL] restarting docker..."
    sudo systemctl restart docker
  fi

  sleep 10
done
