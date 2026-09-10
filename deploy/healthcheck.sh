#!/usr/bin/env bash
#
# healthcheck.sh — Sonde OpsTrack : etat des services, endpoint applicatif,
# espace disque et expiration du certificat TLS. Les anomalies sont journalisees
# dans syslog (tag opstrack-health, priorite user.err) pour exploitation/alerte.
# Code de sortie non nul si au moins une anomalie est detectee.
#
#   bash deploy/healthcheck.sh
#
set -uo pipefail

DOMAIN="${DOMAIN:-eval-dfs-p-tpl-20265-07.it-students.fr}"
DISK_MAX="${DISK_MAX:-90}"        # seuil d'alerte occupation disque (%)
CERT_MIN_DAYS="${CERT_MIN_DAYS:-15}"
FAIL=0

alert() { logger -t opstrack-health -p user.err "ALERTE: $1" 2>/dev/null || true; echo "ALERTE: $1"; FAIL=1; }
ok()    { echo "OK: $1"; }

# 1. Services critiques
for svc in apache2 mysql mongod redis-server opstrack-dispatch-dashboard; do
  if systemctl is-active --quiet "$svc"; then ok "service $svc actif"; else alert "service $svc INACTIF"; fi
done

# 2. Endpoint applicatif public
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${DOMAIN}/api/health" || echo 000)
[ "$code" = "200" ] && ok "https api/health = 200" || alert "https api/health = ${code}"

# 3. Espace disque racine
use=$(df / | awk 'END{gsub("%","",$5); print $5}')
if [ "${use:-100}" -lt "${DISK_MAX}" ]; then ok "disque / a ${use}%"; else alert "disque / sature (${use}%)"; fi

# 4. Expiration du certificat TLS
exp=$(echo | openssl s_client -servername "${DOMAIN}" -connect "${DOMAIN}:443" 2>/dev/null \
      | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [ -n "${exp}" ]; then
  days=$(( ( $(date -d "${exp}" +%s) - $(date +%s) ) / 86400 ))
  if [ "${days}" -ge "${CERT_MIN_DAYS}" ]; then ok "certificat TLS valide ${days} j"; else alert "certificat TLS expire dans ${days} j"; fi
else
  alert "impossible de lire le certificat TLS"
fi

exit "${FAIL}"
