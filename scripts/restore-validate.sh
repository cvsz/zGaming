#!/usr/bin/env bash
set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "Usage: $0 <backup.sql.gz>" >&2
  exit 1
fi

: "${DB_HOST:=127.0.0.1}"
: "${DB_PORT:=3306}"
: "${DB_USER:=casino}"
: "${DB_PASSWORD:=casino}"
RESTORE_DB="${RESTORE_DB:-casino_restore_validation}"

MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e "DROP DATABASE IF EXISTS ${RESTORE_DB}; CREATE DATABASE ${RESTORE_DB};"
zcat "$FILE" | MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$RESTORE_DB"
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -D "$RESTORE_DB" -e "SELECT COUNT(*) AS wallets FROM wallets; SELECT COUNT(*) AS tx_count FROM internal_transactions;"

echo "restore_validation_ok db=$RESTORE_DB from=$FILE"
