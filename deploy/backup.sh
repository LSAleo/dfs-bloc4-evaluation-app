#!/usr/bin/env bash
#
# backup.sh — Sauvegarde OpsTrack : MySQL + MongoDB + secrets (.env).
# Destinee a etre planifiee par cron (voir deploy/README ou livrable 04).
#
#   sudo BACKUP_DIR=/var/backups/opstrack bash deploy/backup.sh
#
set -euo pipefail

APP_DIR="${APP_DIR:-/var/www/opstrack}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/opstrack}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="${BACKUP_DIR}/${STAMP}"

env_get() { grep -E "^$1=" "${APP_DIR}/.env" | head -1 | cut -d= -f2-; }

DB_DATABASE="$(env_get DB_DATABASE)"
DB_USERNAME="$(env_get DB_USERNAME)"
DB_PASSWORD="$(env_get DB_PASSWORD)"
MONGO_DB="$(env_get MONGODB_DATABASE)"

mkdir -p "${DEST}"

# 1. Base relationnelle (dump transactionnel coherent)
# --no-tablespaces : l'utilisateur applicatif est volontairement limite a sa base
# (pas de privilege global PROCESS requis par le dump des tablespaces).
mysqldump -u"${DB_USERNAME}" -p"${DB_PASSWORD}" --single-transaction --quick --no-tablespaces \
  "${DB_DATABASE}" | gzip > "${DEST}/mysql-${DB_DATABASE}.sql.gz"

# 2. Base NoSQL (journaux techniques)
if command -v mongodump >/dev/null 2>&1; then
  mongodump --quiet --db="${MONGO_DB}" --gzip \
    --archive="${DEST}/mongo-${MONGO_DB}.archive.gz" \
    || echo "[warn] mongodump indisponible ou base vide"
fi

# 3. Secrets et configuration (droits restreints)
cp "${APP_DIR}/.env" "${DEST}/env.backup"
chmod 600 "${DEST}/env.backup"

# 4. Retention : purge des sauvegardes plus anciennes que RETENTION_DAYS jours
find "${BACKUP_DIR}" -maxdepth 1 -type d -name '20*' -mtime "+${RETENTION_DAYS}" \
  -exec rm -rf {} + 2>/dev/null || true

echo "[ok] sauvegarde ${DEST} ($(du -sh "${DEST}" | cut -f1))"
