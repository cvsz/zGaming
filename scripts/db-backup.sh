#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-./backups}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="$BACKUP_DIR/zgaming-${TS}.sql.gz"
TMP_FILE="$OUT_FILE.tmp"
mkdir -p "$BACKUP_DIR"

: "${DB_HOST:=127.0.0.1}"
: "${DB_PORT:=3306}"
: "${DB_NAME:=casino}"
: "${DB_USER:=casino}"
: "${DB_PASSWORD:=casino}"

MYSQL_PWD="$DB_PASSWORD" mysqldump \
  --single-transaction \
  --quick \
  --skip-lock-tables \
  --hex-blob \
  --routines \
  --triggers \
  -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" | gzip -9 > "$TMP_FILE"

mv "$TMP_FILE" "$OUT_FILE"
sha256sum "$OUT_FILE" > "$OUT_FILE.sha256"
echo "backup_created=$OUT_FILE"
