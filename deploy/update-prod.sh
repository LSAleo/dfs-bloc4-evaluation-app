#!/usr/bin/env bash
#
# update-prod.sh — Mise a jour d'un environnement OpsTrack deja provisionne.
# Appele par le pipeline CI/CD (via SSH) ou manuellement.
#
#   bash deploy/update-prod.sh [REF]      # REF = branche/tag, defaut: main
#
# Le script sert LES DEUX environnements (le nom est historique) : c'est ce qui
# permet au pipeline de promouvoir la meme reference de la qualification vers la
# production en rejouant strictement la meme procedure. L'environnement cible se
# choisit par variables :
#
#   DOMAIN=eval-dfs-q-tpl-20265-07.it-students.fr SCHEME=http \
#     bash deploy/update-prod.sh main            # qualification (pas de TLS)
#   bash deploy/update-prod.sh main              # production (defauts ci-dessous)
#
# Deploie REF, verifie par smoke test, et effectue un ROLLBACK automatique vers
# la version precedente si la CONSTRUCTION ou le SMOKE TEST echoue.
#
set -euo pipefail

REF="${1:-main}"
APP_DIR="${APP_DIR:-/var/www/opstrack}"
DOMAIN="${DOMAIN:-eval-dfs-p-tpl-20265-07.it-students.fr}"
SCHEME="${SCHEME:-https}"
MS="${APP_DIR}/microservices/dispatch-dashboard"
cd "${APP_DIR}"

PREV_SHA="$(git rev-parse HEAD)"
echo "==> Environnement    : ${SCHEME}://${DOMAIN}"
echo "==> Version courante : ${PREV_SHA}"
echo "==> Deploiement de   : ${REF}"

# `|| return 1` sur chaque etape : la fonction est appelee dans un contexte
# conditionnel, ou bash desactive `set -e`. Sans ces gardes, l'echec d'une etape
# n'interromprait pas les suivantes et le rollback ne serait pas declenche.
build_release() {
  composer install --no-dev --optimize-autoloader --no-interaction \
    --ignore-platform-req=ext-mongodb || return 1
  php artisan migrate --force        || return 1
  php artisan config:clear           || return 1
  ( cd "${MS}" && npm install --no-audit --no-fund && npm run build ) || return 1
  sudo systemctl restart opstrack-dispatch-dashboard || return 1
  sudo systemctl reload apache2      || return 1
}

# Smoke test avec attente active : le microservice Next.js met quelques
# secondes a ecouter apres un restart. On reessaie jusqu'a 10 fois (30 s max).
smoke_test() {
  local base="${SCHEME}://${DOMAIN}" i
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

# Rollback : restaure le code precedent, le reconstruit et le verifie.
# Couvre aussi bien un echec de construction qu'un echec de smoke test.
rollback() {
  echo "!! ECHEC ($1) -> rollback vers ${PREV_SHA:0:7}"
  git reset --hard "${PREV_SHA}" --quiet
  if build_release && smoke_test; then
    echo "==> Rollback reussi : ${DOMAIN} restaure sur ${PREV_SHA:0:7}."
  else
    echo "!! Rollback egalement en echec : intervention manuelle requise."
  fi
  exit 1
}

# --- Deploiement de la nouvelle version ---
git fetch --all --quiet
git reset --hard "origin/${REF}" --quiet 2>/dev/null || git reset --hard "${REF}" --quiet
NEW_SHA="$(git rev-parse HEAD)"

echo "==> Construction..."
build_release || rollback "construction"

echo "==> Smoke test..."
smoke_test || rollback "smoke test"

echo "==> OK : ${REF} (${NEW_SHA:0:7}) est deploye sur ${DOMAIN}."
