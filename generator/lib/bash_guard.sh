#!/usr/bin/env bash
set -Eeuo pipefail
(( BASH_VERSINFO[0] >= 5 )) || {
  echo "❌ Bash >= 5 required. Current: $BASH_VERSION" >&2
  exit 1
}
