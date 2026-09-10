#!/usr/bin/env bash
#
# update-prod.sh — Mise a jour de la production deja provisionnee.
# Appele par le pipeline CI/CD (via SSH) ou manuellement.
#
#   bash deploy/update-prod.sh [REF]      # REF = branche/tag, defaut: main
#
# Deploie REF, verifie par smoke test, et effectue un ROLLBACK automatique
# vers la version precedente si le smoke test echoue.
#
set -euo pipefail

REF="${1:-main}"
APP_DIR="${APP_DIR:-/var/www/opstrack}"
DOMAIN="${DOMAIN:-eval-dfs-p-tpl-20265-07.it-students.fr}"
MS="${APP_DIR}/microservices/dispatch-dashboard"
cd "${APP_DIR}"

PREV_SHA="$(git rev-parse HEAD)"
echo "==> Version courante : ${PREV_SHA}"
echo "==> Deploiement de   : ${REF}"

build_release() {
  composer install --no-dev --optimize-autoloader --no-interaction --ignore-platform-req=ext-mongodb
  php artisan migrate --force
  php artisan config:clear
  ( cd "${MS}" && npm install --no-audit --no-fund && npm run build )
  sudo systemctl restart opstrack-dispatch-dashboard
  sudo systemctl reload apache2
}

# Smoke test avec attente active : le microservice Next.js met quelques
# secondes a ecouter apres un restart. On reessaie jusqu'a 10 fois (30 s max).
smoke_test() {
  local base="https://${DOMAIN}" i
  for i in $(seq 1 10); do
    if curl -fsS "${base}/api/health" | grep -q '"status":"ok"' \
       && curl -fsS -o /dev/null "${base}/" \
       && curl -fsS -o /dev/null "${base}/dispatch-dashboard"; then
      return 0
    fi
    echo "   ...services pas encore prets (tentative ${i}/10)"; sleep 3
  done
  return 1
}

# --- Deploiement de la nouvelle version ---
git fetch --all --quiet
git reset --hard "origin/${REF}" --quiet 2>/dev/null || git reset --hard "${REF}" --quiet
NEW_SHA="$(git rev-parse HEAD)"
build_release

# --- Verification + rollback automatique ---
echo "==> Smoke test..."
if smoke_test; then
  echo "==> OK : ${REF} (${NEW_SHA:0:7}) est en production."
else
  echo "!! Smoke test en ECHEC -> rollback vers ${PREV_SHA:0:7}"
  git reset --hard "${PREV_SHA}" --quiet
  build_release
  if smoke_test; then
    echo "==> Rollback reussi : production restauree sur ${PREV_SHA:0:7}."
  else
    echo "!! Rollback egalement en echec : intervention manuelle requise."
  fi
  exit 1
fi
