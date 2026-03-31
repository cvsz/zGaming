#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  JWT_SECRET
  JWT_ISSUER
  JWT_AUDIENCE
  INTERNAL_WEBHOOK_SECRET
  INTERNAL_ADMIN_TOKEN
)

missing=()
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    missing+=("$var_name")
  fi
done

if (( ${#missing[@]} > 0 )); then
  printf 'Missing required environment variables:\n' >&2
  printf ' - %s\n' "${missing[@]}" >&2
  exit 1
fi

echo "Environment validation passed (${#required_vars[@]} required variables present)."
